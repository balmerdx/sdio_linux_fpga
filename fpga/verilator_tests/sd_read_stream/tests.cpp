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

void VerilogTest::init(Vsd_read_stream *top)
{
    this->top = top;
}

TestSilence::TestSilence(vluint64_t duration)
    : duration(duration)
{

}


void TestSilence::start()
{
    start_time = main_time;
    printf("TestSilence started");
    top->sd_serial = 1;
}

void TestSilence::beforeEval()
{

}

bool TestSilence::afterEval()
{

    if(top->data_strobe!=0)
    {
        printf("TestSilence fail sd_serial\n");
        _fail = true;
    }

    if(top->read_error!=0)
    {
        printf("TestSilence fail write_enabled\n");
        _fail = true;
    }

    return !(_fail || (main_time>=start_time+duration));
}

////////////////////////////TestRead////////////////////////////
TestRead::TestRead(uint64_t data38, Bad bad)
    : data38(data38)
    , bad(bad)
{
    dataToSend = make_sd_command(data38, bad==Bad::Direction?false:true);

    if(bad==Bad::CRC)
        dataToSend = dataToSend&~0x8Eull;
    if(bad==Bad::EndBit)
        dataToSend = dataToSend&~(1ull);
}

void TestRead::start()
{
    top->sd_serial = 1;
    prev_sd_clock = top->sd_clock;
    currentBit = 48;
    minTicks = 40;

    top->read_enabled = (bad==Bad::ReadDisabled)?0:1;
}

void TestRead::beforeEval()
{
    if(clockFalling())
        return;

    if(prev_sd_clock==1 && top->sd_clock==0)
    {
        if(currentBit>0)
            currentBit--;
        top->sd_serial = (dataToSend>>currentBit)&1;
    }

    prev_sd_clock = top->sd_clock;

}

bool TestRead::afterEval()
{
    if(_fail)
        return false;

    if(!clockRising())
        return true;

    if(top->data_strobe)
    {
        if(top->read_error)
        {
            printf("TestRead data_strobe==1 && read_error==1");
            _fail = true;
            return false;
        }

        data_ok = top->data==data38;
        if(!data_ok)
        {
            printf("TestRead top->data!=data38");
            _fail = true;
            return false;
        }
    }

    if(top->read_error)
    {
        if(bad==Bad::None)
        {
            printf("TestRead read error");
            _fail = true;
            return false;
        } else {
            error_ok = true;
        }
    }

    if(currentBit==0)
        minTicks--;


    if(minTicks==0)
    {
        if(bad==Bad::None)
        {
            if(!data_ok)
            {
                printf("TestRead data not received");
                _fail = true;
                return false;
            }
        } else
        {
            if(bad==Bad::ReadDisabled)
            {
                if(error_ok || data_ok)
                {
                    printf("TestRead ReadDisabled, but data received!");
                    _fail = true;
                    return false;
                }

            } else
            {
                if(!error_ok)
                {
                    printf("TestRead error not received");
                    _fail = true;
                    return false;
                }
            }
        }
    }

    return minTicks>0;
}
