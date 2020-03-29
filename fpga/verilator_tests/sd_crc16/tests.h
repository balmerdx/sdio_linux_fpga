#pragma once

#include "Vsd_crc16.h"
#include <stdint.h>
#include <vector>
#include "crc16.h"

class VerilogTest
{
public:
    VerilogTest();
    virtual ~VerilogTest();

    virtual void init(Vsd_crc16* top);
    virtual void start()=0;
    virtual void beforeEval()=0;
    //return false if test completed
    virtual bool afterEval()=0;
    virtual bool fail() { return _fail; }
protected:
    Vsd_crc16* top = nullptr;
    bool _fail = false;
};

class TestClear : public VerilogTest
{
public:
    TestClear(vluint64_t duration = 32);
    void start() override;

    void beforeEval() override;
    bool afterEval() override;
protected:
    vluint64_t start_time;
    vluint64_t duration;
};


class TestCrc : public VerilogTest
{
public:
    TestCrc();

    void start() override;
    void beforeEval() override;
    bool afterEval() override;

protected:
    bool started = false;
    uint16_t currentSeed;
    uint8_t currentBit;
};
