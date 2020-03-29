################################################################################
#
# balmer_sdio_uart
#
################################################################################

BALMER_SDIO_UART_VERSION = 1.0
BALMER_SDIO_UART_SITE = $(BR2_EXTERNAL_LPI_PATH)/balmer_sdio_uart
BALMER_SDIO_UART_SITE_METHOD = local

$(eval $(kernel-module))
$(eval $(generic-package))
