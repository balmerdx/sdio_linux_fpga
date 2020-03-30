#pragma once

#include "Vsd_response_stream_dat.h"
#include <stdint.h>
#include <vector>
#include <array>

class VerilogTest
{
public:
    VerilogTest();
    virtual ~VerilogTest();

    virtual void init(Vsd_response_stream_dat* top);
    virtual void start()=0;
    virtual void beforeEval()=0;
    //return false if test completed
    virtual bool afterEval()=0;
    virtual bool fail() { return _fail; }
protected:
    Vsd_response_stream_dat* top = nullptr;
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
    TestWrite(std::vector<uint8_t> data);

    void start() override;
    void beforeEval() override;
    bool afterEval() override;

protected:
    std::vector<uint8_t> data;
    std::vector<uint8_t> dataReceived;
    size_t currentIndex = 0;

    std::array<uint16_t, 4> crcCalculated;
    std::array<uint16_t, 4> crcReceived;
    int crcReceivedIdx = 0;

    uint8_t prev_sd_clock;
    int halfReceived = 0;
    uint8_t curReceived = 0;
    bool writeEnabledFound = false;

    int waitAterWrite = 0;
};


class TestCrcStatus : public VerilogTest
{
public:
    TestCrcStatus(bool positive);

    void start() override;
    void beforeEval() override;
    bool afterEval() override;

protected:
    const int bitsCount = 5;
    bool positive;
    uint8_t data;
    uint8_t dataReceived;
    size_t currentIndex = 0;

    int dataReceivedIdx = 0;

    uint8_t prev_sd_clock;
    bool writeEnabledFound = false;

    int waitAterWrite = 0;
};
