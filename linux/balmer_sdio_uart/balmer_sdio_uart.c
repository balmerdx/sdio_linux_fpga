/*
 * Author:	Dmitriy 'Balmer' Poskryakov
 * Created:	2020
 * 2020 Balmer - use for own SDIO UART
 *
 * Based on Nicolas Pitre sdio_uart.c
 *
 * Based on drivers/serial/8250.c and drivers/serial/serial_core.c
 * by Russell King.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 * 
 */


#include <linux/module.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/mutex.h>
#include <linux/seq_file.h>
#include <linux/circ_buf.h>
#include <linux/kfifo.h>
#include <linux/slab.h>
#include <linux/cdev.h>

#include <linux/mmc/core.h>
#include <linux/mmc/card.h>
#include <linux/mmc/sdio_func.h>
#include <linux/mmc/sdio_ids.h>
#include <linux/uaccess.h>

#define MY_REG_RX 0
#define MY_REG_TX 0
#define MY_REG_STATUS 1

bool debug_info = false;

//data ready
#define BIT_STATUS_DR 0x01
//transmit empty
#define BIT_STATUS_THRE 0x01

#define UART_NR		4	/* Number of UARTs this driver can handle */

#define FIFO_SIZE	PAGE_SIZE
#define WAKEUP_CHARS	256

struct sdio_uart_port {
    uint32_t            magic;
    unsigned int		index;
	struct sdio_func	*func;
	struct mutex		func_lock;
	struct task_struct	*in_sdio_uart_irq;
	struct kfifo		xmit_fifo;
    struct kfifo		read_fifo;
    spinlock_t		write_lock; //actually read/write lock
    struct device   *file_dev;
    struct cdev c_dev;
};

static dev_t balmer_dev_t = 0;
struct class *balmer_class = 0;


static struct sdio_uart_port *sdio_uart_table[UART_NR];
static DEFINE_SPINLOCK(sdio_uart_table_lock);

static int sdio_uart_add_port(struct sdio_uart_port *port)
{
	int index, ret = -EBUSY;

	mutex_init(&port->func_lock);
	spin_lock_init(&port->write_lock);
	if (kfifo_alloc(&port->xmit_fifo, FIFO_SIZE, GFP_KERNEL))
		return -ENOMEM;

    if (kfifo_alloc(&port->read_fifo, FIFO_SIZE, GFP_KERNEL))
    {
        kfifo_free(&port->xmit_fifo);
        return -ENOMEM;
    }

	spin_lock(&sdio_uart_table_lock);
	for (index = 0; index < UART_NR; index++) {
		if (!sdio_uart_table[index]) {
			port->index = index;
			sdio_uart_table[index] = port;
			ret = 0;
			break;
		}
	}
	spin_unlock(&sdio_uart_table_lock);

	return ret;
}

static void sdio_uart_port_remove(struct sdio_uart_port *port)
{
	struct sdio_func *func;

	spin_lock(&sdio_uart_table_lock);
	sdio_uart_table[port->index] = NULL;
	spin_unlock(&sdio_uart_table_lock);

	/*
	 * We're killing a port that potentially still is in use by
	 * the tty layer. Be careful to prevent any further access
	 * to the SDIO function and arrange for the tty layer to
	 * give up on that port ASAP.
	 * Beware: the lock ordering is critical.
	 */
	mutex_lock(&port->func_lock);
	func = port->func;
	sdio_claim_host(func);
	port->func = NULL;
	mutex_unlock(&port->func_lock);
	sdio_release_irq(func);
	sdio_disable_func(func);
	sdio_release_host(func);
}

static int sdio_uart_claim_func(struct sdio_uart_port *port)
{
	mutex_lock(&port->func_lock);
	if (unlikely(!port->func)) {
		mutex_unlock(&port->func_lock);
		return -ENODEV;
	}
	if (likely(port->in_sdio_uart_irq != current))
		sdio_claim_host(port->func);
	mutex_unlock(&port->func_lock);
	return 0;
}

static inline void sdio_uart_release_func(struct sdio_uart_port *port)
{
	if (likely(port->in_sdio_uart_irq != current))
		sdio_release_host(port->func);
}

static inline u8 sdio_in(struct sdio_uart_port *port, int offset)
{
    u8 c;
    c = sdio_readb(port->func, offset, NULL);
	return c;
}

static inline void sdio_out(struct sdio_uart_port *port, int offset, u8 value)
{
    sdio_writeb(port->func, value, offset, NULL);
}
/*
static void sdio_uart_receive_chars(struct sdio_uart_port *port,
				    unsigned int *status)
{
#define RECEIVE_BUFFER_SIZE 256
    int ret;
    int count = 0;
    uint8_t data[RECEIVE_BUFFER_SIZE];

    if(0)
    {
        do {
            data[count++] = sdio_in(port, MY_REG_RX);
            *status = sdio_in(port, MY_REG_STATUS);
        } while ((*status & BIT_STATUS_DR) && (count < RECEIVE_BUFFER_SIZE));

    } else
    {
        unsigned int addr = 0;
        ret = sdio_readsb(port->func, data, addr, RECEIVE_BUFFER_SIZE);
        if(debug_info) pr_info("SDIO Driver: sdio_uart_receive_chars sdio_readsb=%i\n", ret);
        if(ret!=0)
            return;
        count = RECEIVE_BUFFER_SIZE;
    }

    //Не проверяем на переполнение
    ret = kfifo_in_locked(&port->read_fifo, data, count, &port->write_lock);
#undef RECEIVE_BUFFER_SIZE
}
*/
static void sdio_uart_transmit_chars(struct sdio_uart_port *port)
{
	struct kfifo *xmit = &port->xmit_fifo;
	int count;
    const int size = 256;
    u8 iobuf[size];
	int len;

    if (!kfifo_len(xmit)) {
		return;
	}

    if(0)
    {
        len = kfifo_out_locked(xmit, iobuf, size, &port->write_lock);
        for (count = 0; count < len; count++) {
            sdio_out(port, MY_REG_TX, iobuf[count]);
        }
    } else
    {
        while(1)
        {
            len = kfifo_out_locked(xmit, iobuf, size, &port->write_lock);
            if(len<=0)
                break;
            sdio_writesb(port->func, 0, iobuf, len);
        }
    }

    //len = kfifo_len(xmit); //test code
}

/*
 * This handles the interrupt from one port.
 */
static void sdio_uart_irq(struct sdio_func *func)
{
	struct sdio_uart_port *port = sdio_get_drvdata(func);
    unsigned int status;

	/*
	 * In a few places sdio_uart_irq() is called directly instead of
	 * waiting for the actual interrupt to be raised and the SDIO IRQ
	 * thread scheduled in order to reduce latency.  However, some
	 * interaction with the tty core may end up calling us back
	 * (serial echo, flow control, etc.) through those same places
	 * causing undesirable effects.  Let's stop the recursion here.
	 */
	if (unlikely(port->in_sdio_uart_irq == current))
		return;

	port->in_sdio_uart_irq = current;
    status = sdio_in(port, MY_REG_STATUS);
    /*
    if (status & BIT_STATUS_DR)
    {
        sdio_uart_receive_chars(port, &status);
    }
    */

    if (status & BIT_STATUS_THRE)
    {
        sdio_uart_transmit_chars(port);
    }

	port->in_sdio_uart_irq = NULL;
}

//Получаем данные напрямую из вызываемой функции
static int sdio_receive_inline(struct sdio_func *func, char* buf, int size)
{
    struct sdio_uart_port *port = sdio_get_drvdata(func);
    int ret;

    if (unlikely(port->in_sdio_uart_irq == current))
        return 0;

    port->in_sdio_uart_irq = current;

    {
        unsigned int addr = 0;
        ret = sdio_readsb(port->func, buf, addr, size);
    }

    port->in_sdio_uart_irq = NULL;

    return (ret==0)?size:0;
}

static int sdio_uart_activate(struct sdio_uart_port *port)
{
	int ret;

    if(debug_info) pr_info("SDIO Driver: sdio_uart_activate start\n");
	kfifo_reset(&port->xmit_fifo);
    kfifo_reset(&port->read_fifo);

	ret = sdio_uart_claim_func(port);
	if (ret)
		return ret;

    if(debug_info) pr_info("SDIO Driver: sdio_uart_activate sdio_uart_claim_func ok\n");

	ret = sdio_enable_func(port->func);
	if (ret)
		goto err1;

    if(debug_info) pr_info("SDIO Driver: sdio_uart_activate sdio_enable_func ok\n");
	ret = sdio_claim_irq(port->func, sdio_uart_irq);
	if (ret)
		goto err2;

    if(debug_info) pr_info("SDIO Driver: sdio_uart_activate sdio_claim_irq ok\n");
    // Kick the IRQ handler once while we're still holding the host lock
	sdio_uart_irq(port->func);

    if(debug_info) pr_info("SDIO Driver: sdio_uart_activate sdio_uart_irq complete\n");
	sdio_uart_release_func(port);

    if(debug_info) pr_info("SDIO Driver: sdio_uart_activate complete\n");
	return 0;

err2:
	sdio_disable_func(port->func);
err1:
	sdio_uart_release_func(port);
	return ret;
}

static void sdio_uart_shutdown(struct sdio_uart_port *port)
{
	int ret;

	ret = sdio_uart_claim_func(port);
	if (ret)
		return;

    sdio_release_irq(port->func);
	sdio_disable_func(port->func);

	sdio_uart_release_func(port);
}

//Пока оставить для примера
static int sdio_uart_write(struct sdio_uart_port *port, const unsigned char *buf,
			   int count)
{
	int ret;

	if (!port->func)
		return -ENODEV;

	ret = kfifo_in_locked(&port->xmit_fifo, buf, count, &port->write_lock);

    {
		int err = sdio_uart_claim_func(port);
		if (!err) {
			sdio_uart_irq(port->func);
			sdio_uart_release_func(port);
		} else
			ret = err;
	}

	return ret;
}

static int sdio_uart_read(struct sdio_uart_port *port, char *buf, int count)
{
    int ret;

    if (!port->func)
        return -ENODEV;

    int err = sdio_uart_claim_func(port);
    if (!err)
    {
        ret = sdio_receive_inline(port->func, buf, count);
        sdio_uart_release_func(port);
    } else
        ret = err;

    return ret;
}

/*
static int sdio_uart_write_room(struct sdio_uart_port *port)
{
	return FIFO_SIZE - kfifo_len(&port->xmit_fifo);
}
*/

static int sdio_file_open(struct inode *inode, struct file *file)
{
    if(debug_info)pr_info("SDIO Driver: open()\n");
    struct sdio_uart_port *port;
    port = container_of(inode->i_cdev, struct sdio_uart_port, c_dev);
    file->private_data = port;
    if(debug_info)pr_info("SDIO Driver: open() portidx=%u magic=%x\n", port->index, port->magic);
    return sdio_uart_activate(port);
}

static int sdio_file_close(struct inode *inode, struct file *file)
{
    if(debug_info)pr_info("SDIO Driver: close()\n");
    struct sdio_uart_port *port;
    port = container_of(inode->i_cdev, struct sdio_uart_port, c_dev);
    if(debug_info)pr_info("SDIO Driver: close() portidx=%u\n", port->index);
    sdio_uart_shutdown(port);
    return 0;
}

static ssize_t sdio_file_read(struct file *file, char __user *buf, size_t len, loff_t *off)
{
    size_t len_cur;
    size_t sum_len_out = 0;
    int len_out;
    char data[4096];
    struct sdio_uart_port *port = file->private_data;
    if(debug_info) pr_info("SDIO Driver: read() magic=%x buf=%x len=%u\n", port->magic, (uint32_t)buf, (uint32_t)len);

    while(1)
    {
        len_cur = len;
        if(len_cur>sizeof(data))
            len_cur = sizeof(data);

        len_out = sdio_uart_read(port, data, len_cur);
        if(len_out<=0)
            break;
        if (copy_to_user(buf, data, len_out))
            return -EFAULT;
        sum_len_out += len_out;
        if(len >= len_out)
            break;
        len -= len_out;
        buf += len_out;
    }

    if(debug_info) pr_info("SDIO Driver: read() sum_len_out=%u\n", (uint32_t)sum_len_out);
    return sum_len_out;
}

static ssize_t sdio_file_write(
        struct file *file, const char __user *buf, size_t len, loff_t *off)
{
    struct sdio_uart_port *port = file->private_data;
    int ret = 0;
    ssize_t write_size = 0;
    if(debug_info) pr_info("SDIO Driver: write()\n");
    size_t len_write;

    uint8_t data[4096];

    while(len>0)
    {
        len_write = len;
        if(len_write > sizeof(data))
            len_write = sizeof(data);

        ret = copy_from_user(data, buf, len_write);
        if(ret==0)
            write_size += sdio_uart_write(port, data, len_write);
        else
            pr_info("SDIO Driver: write() copy_from_user failed\n");

        buf += len_write;
        len -= len_write;
    }

    if(debug_info) pr_info("SDIO Driver: write() len=%u, ret=%i\n", (uint32_t)len, ret);
    return write_size;
}

static const struct file_operations sdio_uart_proc_fops = {
	.owner		= THIS_MODULE,
    .open		= sdio_file_open,
    .release    = sdio_file_close,
    .read		= sdio_file_read,
    .write      = sdio_file_write,
};

static int sdio_uart_probe(struct sdio_func *func,
			   const struct sdio_device_id *id)
{
	struct sdio_uart_port *port;
	int ret;
    dev_t dev_idx;

    if(debug_info)pr_warn("sdio_uart_probe start");

	port = kzalloc(sizeof(struct sdio_uart_port), GFP_KERNEL);
	if (!port)
		return -ENOMEM;

    port->magic = 0x12345678;

	if (func->class == SDIO_CLASS_UART) {
		pr_warn("%s: balmer own driver init UART over SDIO\n",
			sdio_func_id(func));
	} else {
        ret = -EINVAL;
        goto err1;
	}

	port->func = func;
	sdio_set_drvdata(func, port);

	ret = sdio_uart_add_port(port);
	if (ret) {
		kfree(port);
        return ret;
    }

    dev_idx = balmer_dev_t+port->index;

    port->file_dev = device_create(balmer_class, NULL, dev_idx, NULL, "balmerSDIO%d", port->index);
    if (IS_ERR(port->file_dev))
    {
        sdio_uart_port_remove(port);
        ret = PTR_ERR(port->file_dev);
    }

    if(debug_info)pr_warn("sdio_uart_probe device_create ok");
    //port->file_dev->driver_data = port;

    cdev_init(&port->c_dev, &sdio_uart_proc_fops);
    ret = cdev_add(&port->c_dev, dev_idx, 1);
    if (ret < 0) {
        goto err2;
    }

    if(debug_info)pr_warn("sdio_uart_probe all ok");
	return ret;
err2:
    device_destroy(balmer_class, dev_idx);
err1:
    kfree(port);
    return ret;
}

static void sdio_uart_remove(struct sdio_func *func)
{
    if(debug_info)pr_warn("sdio_uart_remove start");
	struct sdio_uart_port *port = sdio_get_drvdata(func);

    device_destroy(balmer_class, balmer_dev_t+port->index);
    kfifo_free(&port->read_fifo);
    kfifo_free(&port->xmit_fifo);
    kfree(port);

    sdio_uart_port_remove(port);
    if(debug_info)pr_warn("sdio_uart_remove complete");
}

static const struct sdio_device_id sdio_uart_ids[] = {
	{ SDIO_DEVICE_CLASS(SDIO_CLASS_UART) },
	{ /* end: all zeroes */				 },
};

MODULE_DEVICE_TABLE(sdio, sdio_uart_ids);

static struct sdio_driver sdio_uart_driver = {
	.probe		= sdio_uart_probe,
	.remove		= sdio_uart_remove,
	.name		= "sdio_uart",
	.id_table	= sdio_uart_ids,
};

static int __init sdio_uart_init(void)
{
	int ret;
    if(debug_info)pr_warn("sdio_uart_init start");
    if ((ret = alloc_chrdev_region(&balmer_dev_t, 0, 1, "balmer_dev_t")) < 0)
        return ret;

    if(debug_info)pr_warn("sdio_uart_init alloc_chrdev_region ok");
    balmer_class = class_create(THIS_MODULE, "balmer_sdio");

    if (IS_ERR(balmer_class))
    {
        ret = PTR_ERR(balmer_class);
        goto err1;
    }

	ret = sdio_register_driver(&sdio_uart_driver);
	if (ret)
		goto err2;

    if(debug_info)pr_warn("sdio_uart_init complete");
	return 0;
err2:
    class_destroy(balmer_class);
    balmer_class = 0;
err1:
    unregister_chrdev_region(balmer_dev_t, UART_NR);
    balmer_dev_t = 0;
    return ret;
}

static void __exit sdio_uart_exit(void)
{
    if(balmer_class)
    {
        class_destroy(balmer_class);
        balmer_class = 0;
    }

    if(balmer_dev_t)
    {
        unregister_chrdev_region(balmer_dev_t, UART_NR);
        balmer_dev_t = 0;
    }

	sdio_unregister_driver(&sdio_uart_driver);
}

module_init(sdio_uart_init);
module_exit(sdio_uart_exit);

//MODULE_AUTHOR("Nicolas Pitre");
MODULE_AUTHOR("Dmitriy 'balmer' Poskryakov");
MODULE_LICENSE("GPL");
