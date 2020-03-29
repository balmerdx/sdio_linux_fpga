#include "tests.h"
#include "crc7.h"

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

void VerilogTest::init(Vsd_response_stream *top)
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
    printf("TestSilence started\n");
}

void TestSilence::beforeEval()
{

}

bool TestSilence::afterEval()
{

    if(top->sd_serial!=1)
    {
        printf("TestSilence fail sd_serial\n");
        _fail = true;
    }

    if(top->write_enabled!=0)
    {
        printf("TestSilence fail write_enabled\n");
        _fail = true;
    }

    return !(_fail || (main_time>=start_time+duration));
}

////////////////////////////TestWrite////////////////////////////

TestWrite::TestWrite(uint64_t data38)
    : data38(data38)
{

    dataOriginal = make_sd_command(data38, false);
    dataReceived = 0;
}

void TestWrite::start()
{
    top->data = data38;

    prev_sd_clock = top->sd_clock;
}

void TestWrite::beforeEval()
{
    if(clockFalling())
        return;

    if(strobe_time==0)
        top->data_strobe = 1;
    else
        top->data_strobe = 0;

    strobe_time++;

}

bool TestWrite::afterEval()
{
    if(_fail)
        return false;

    if(!clockRising())
        return true;

    if(prev_sd_clock==1 && top->sd_clock==0)
    {
        if(top->write_enabled)
        {
            bool is_pre_bit = bits_received==0 && top->sd_serial==1;
            bool is_post_bit = bits_received==48 && top->sd_serial==1;
            if(!is_pre_bit && !is_post_bit)
            {
                dataReceived = (dataReceived<<1)|top->sd_serial;
                bits_received++;
            }
        }
    }

    prev_sd_clock = top->sd_clock;

    minTicks--;

    if(minTicks==0)
    {
        if(top->write_enabled)
        {
            printf("Error: top->write_enabled==1 long time\n");
            _fail = true;
        }

        if(bits_received!=48)
        {
            printf("Error: bits_received!=48 bits_received=%i\n", bits_received);
            _fail = true;
        }

        if(dataOriginal!=dataReceived)
        {
            printf("dataOriginal!=dataReceived\n");
            printf(" original=0x%lx\n", dataOriginal);
            printf(" received=0x%lx\n", dataReceived);
            _fail = true;
        }
    }

    return minTicks>0;
}
