#include "tests.h"

#include "../sd_response_stream/crc7.h"

//Global time counter
//Время идет по пол такта.
//Тоесть за один такт main_time изменяется на 2
//Несетные - clock = 1, четные clock = 0
extern vluint64_t main_time;
bool clockRising() { return (main_time&1)==1; }
bool clockFalling() { return (main_time&1)==0; }
//bool clockSck() { return (main_time/2)%32==1; }
//bool clockSck() { return (main_time/2)%4==1; }
bool clockSck() { return (main_time/2)%2==1; }

VerilogTest::VerilogTest()
{
}

VerilogTest::~VerilogTest()
{
}

void VerilogTest::init(Vsd_crc16 *top)
{
    this->top = top;
}

TestClear::TestClear(vluint64_t duration)
    : duration(duration)
{

}


void TestClear::start()
{
    start_time = main_time;
    printf("TestClear started");
    top->clear = 1;
    top->enable = 0;
    top->crc = 0x1234;
}

void TestClear::beforeEval()
{
}

bool TestClear::afterEval()
{
    if(!clockRising())
        return true;

    if(top->crc!=0)
    {
        printf("TestClear crc not zero!\n");
        _fail = true;
    }

    return !(_fail || (main_time>=start_time+duration));
}

////////////////////////////TestCrc////////////////////////////

TestCrc::TestCrc()
{
}

void TestCrc::start()
{
    printf("TestCrc started");
    top->clear = 0;
    top->enable = 0;

    currentSeed = 0;
    currentBit = 0;
}

void TestCrc::beforeEval()
{
    if(clockRising())
        return;

    started = true;
    top->enable = 1;
    top->crc = currentSeed;
    top->in = currentBit;
}

bool TestCrc::afterEval()
{
    if(_fail)
        return false;

    if(clockFalling())
        return true;

    if(!started)
        return true;

    uint16_t expectedValue = crc16_1bit(currentSeed, currentBit);
    if(top->crc != expectedValue)
    {
        printf("TestClear crc not equal %x!=%x\n", (uint32_t)top->crc, (uint32_t)expectedValue);
        printf("    seed=%x, data_in=%x", (uint32_t)currentSeed, (uint32_t)currentBit);

        _fail = true;
        return false;
    }

    currentBit++;
    if(currentBit==2)
    {
        if((currentSeed&0xFF)==0)
            printf("\n    seed=%x", (uint32_t)currentSeed);
        currentBit = 0;
        if(currentSeed==0xFFFF)
            return false;
        currentSeed++;
    }

    return true;
}

