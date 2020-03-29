#include "tests.h"
#include "../sd_crc16/crc16.h"

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

void VerilogTest::init(Vsd_response_stream_dat *top)
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

    if(top->sd_data!=0xF)
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

TestWrite::TestWrite(std::vector<uint8_t> data)
    : data(data)
{
    for(size_t i=0; i<crcReceived.size(); i++)
        crcReceived[i] = 0;

    for(size_t i=0; i<crcCalculated.size(); i++)
        crcCalculated[i] = 0;

    for(uint8_t d : data)
    {
        uint8_t nibble = d>>4;
        for(size_t i=0; i<crcCalculated.size(); i++)
            crcCalculated[i] = crc16_1bit(crcCalculated[i], (nibble>>i)&1);

        nibble = d&0xF;

        for(size_t i=0; i<crcCalculated.size(); i++)
            crcCalculated[i] = crc16_1bit(crcCalculated[i], (nibble>>i)&1);
    }
}

void TestWrite::start()
{
    top->start_write = 1;
    top->data_empty = 0;
    top->data_strobe = 0;

    prev_sd_clock = top->sd_clock;
}

void TestWrite::beforeEval()
{
    if(clockFalling())
        return;
}

bool TestWrite::afterEval()
{
    if(_fail)
        return false;

    if(!clockRising())
        return true;

    top->start_write = 0;
    top->data_strobe = 0;

    if(top->data_req)
    {
        if(currentIndex < data.size())
        {
            top->data =data[currentIndex];
            top->data_strobe = 1;
            currentIndex++;
        } else {
            top->data_empty = 1;
        }
    }


    if(prev_sd_clock==1 && top->sd_clock==0)
    {
        if(top->write_enabled)
        {
            writeEnabledFound = true;
            bool is_pre_bit = halfReceived==0 && top->sd_data==0xF;
            if(!is_pre_bit)
            {
                if(halfReceived==0 && top->sd_data!=0)
                {
                    printf("Error: start top->sd_data!=0\n");
                    _fail = true;
                    return false;
                }

                if(halfReceived>0)
                {
                    size_t curByte = (halfReceived-1)/2;
                    bool isTopHalf = (halfReceived&1)?true:false;
                    if(isTopHalf)
                    {
                        curReceived = top->sd_data<<4;

                        if(crcReceivedIdx==8)
                        {
                            if(top->sd_data!=0xF)
                            {
                                printf("Error: end top->sd_data!=0xF\n");
                                _fail = true;
                                return false;
                            }
                        }
                    } else
                    {
                        uint8_t d = curReceived | top->sd_data;

                        if(dataReceived.size() < data.size())
                        {
                            dataReceived.push_back(d);
                            printf("Info: byte idx=%i received=%x original=%x\n", (int)curByte, dataReceived[curByte], data[curByte]);
                            if(data[curByte]!=dataReceived[curByte])
                            {
                                printf("Error: byte not equal idx=%i received=%x original=%x\n", (int)curByte, dataReceived[curByte], data[curByte]);
                                _fail = true;
                                return false;
                            }
                        } else
                        {
                            if(crcReceivedIdx<8)
                            {
                                uint16_t d16 = d;
                                for(size_t i=0; i<crcReceived.size(); i++)
                                {
                                    int offset = 15-crcReceivedIdx*2;
                                    crcReceived[i] |= ((d16>>(4+i))&1)<<offset;
                                    crcReceived[i] |= ((d16>>i)&1)<<(offset-1);
                                }

                                crcReceivedIdx++;
                            }
                        }

                    }
                }


                halfReceived++;
            }
        } else
        {
            if(writeEnabledFound)
            {
                if(waitAterWrite==0)
                {
                    for(size_t i=0; i<crcReceived.size(); i++)
                        printf("Info: crc %i received=%i calculated=%i\n", (int)i, crcReceived[i], crcCalculated[i]);

                    if(crcReceived!=crcCalculated)
                    {
                        for(size_t i=0; i<crcReceived.size(); i++)
                            printf("Error: crc %i received=%x calculated=%x\n", (int)i, crcReceived[i], crcCalculated[i]);
                        _fail = true;
                        return false;
                    }
                }

                waitAterWrite++;

                if(waitAterWrite>16)
                    return false;
            }
        }
    }

    prev_sd_clock = top->sd_clock;

    return true;
}
