#pragma once

#include "Vsd_read_stream.h"
#include <stdint.h>
#include <vector>

class VerilogTest
{
public:
    VerilogTest();
    virtual ~VerilogTest();

    virtual void init(Vsd_read_stream* top);
    virtual void start()=0;
    virtual void beforeEval()=0;
    //return false if test completed
    virtual bool afterEval()=0;
    virtual bool fail() { return _fail; }
protected:
    Vsd_read_stream* top = nullptr;
    bool _fail = false;
};

//Простейшая проверка. Если ничего не посылаем,
//то SPI никаких сигналов не производит.
class TestSilence : public VerilogTest
{
public:
    TestSilence(vluint64_t duration = 32);
    void start() override;

    void beforeEval() override;
    bool afterEval() override;
protected:
    vluint64_t start_time;
    vluint64_t duration;
};


class TestRead : public VerilogTest
{
public:
    enum class Bad
    {
        None,
        CRC,
        Direction,
        EndBit,
        ReadDisabled,
    };

    //data - 38 бит произвольных данных
    TestRead(uint64_t data38, Bad bad = Bad::None);

    void start() override;
    void beforeEval() override;
    bool afterEval() override;

protected:
    uint64_t data38;
    uint64_t dataToSend;

    int currentBit;
    int minTicks;
    uint8_t prev_sd_clock;

    bool data_ok = false;
    bool error_ok = false;
    Bad bad;
};
