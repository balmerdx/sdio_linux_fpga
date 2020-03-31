#pragma once

#include "Vsd_read_stream_dat.h"
#include <stdint.h>
#include <vector>
#include <array>

class VerilogTest
{
public:
    VerilogTest();
    virtual ~VerilogTest();

    virtual void init(Vsd_read_stream_dat* top);
    virtual void start()=0;
    virtual void beforeEval()=0;
    //return false if test completed
    virtual bool afterEval()=0;
    virtual bool fail() { return _fail; }
protected:
    Vsd_read_stream_dat* top = nullptr;
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
    //data - 38 бит произвольных данных
    TestRead(std::vector<uint8_t> data);

    void start() override;
    void beforeEval() override;
    bool afterEval() override;

protected:
    enum class State
    {
        Starting,
        WriteZero,
        WriteData,
        WriteCRC,
        WriteOne,
        Complete
    };

    std::vector<uint8_t> data;
    std::vector<uint8_t> dataReceived;
    size_t currentIndexX2 = 0;

    std::array<uint16_t, 4> crcCalculated;
    int crcWriteIdx = 0;

    State state = State::Starting;

    uint8_t prev_sd_clock;
    bool writeAllFound = false;

    int waitAterWrite = 3;
};
