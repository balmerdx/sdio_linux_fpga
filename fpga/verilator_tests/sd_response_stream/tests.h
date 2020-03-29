#pragma once

#include "Vsd_response_stream.h"
#include <stdint.h>
#include <vector>

class VerilogTest
{
public:
    VerilogTest();
    virtual ~VerilogTest();

    virtual void init(Vsd_response_stream* top);
    virtual void start()=0;
    virtual void beforeEval()=0;
    //return false if test completed
    virtual bool afterEval()=0;
    virtual bool fail() { return _fail; }
protected:
    Vsd_response_stream* top = nullptr;
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


class TestWrite : public VerilogTest
{
public:
    //data - 38 бит произвольных данных
    TestWrite(uint64_t data38);

    void start() override;
    void beforeEval() override;
    bool afterEval() override;

protected:
    uint64_t data38;
    uint64_t dataOriginal;
    uint64_t dataReceived;

    int minTicks = 240;
    uint8_t prev_sd_clock;
    uint8_t strobe_time = 0;
    int bits_received = 0;
};
