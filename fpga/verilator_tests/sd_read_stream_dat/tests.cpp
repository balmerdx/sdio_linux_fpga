#include "tests.h"
#include "../sd_crc16/crc16.h"

//Global time counter
//Время идет по пол такта.
//Тоесть за один такт main_time изменяется на 2
//Несетные - clock = 1, четные clock = 0
extern vluint64_t main_time;
bool clockRising() { return (main_time&1)==1; }
bool clockFalling() { return (main_time&1)==0; }
bool clockSck() { return (main_time/2)%2==1; }

VerilogTest::VerilogTest()
{
}

VerilogTest::~VerilogTest()
{
}

void VerilogTest::init(Vsd_read_stream_dat *top)
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

    if(top->write_byte_strobe!=0)
    {
        printf("TestSilence fail write_byte_strobe\n");
        _fail = true;
    }

    if(top->write_all_strobe!=0)
    {
        printf("TestSilence fail write_all_strobe\n");
        _fail = true;
    }

    return !(_fail || (main_time>=start_time+duration));
}

////////////////////////////TestRead////////////////////////////

TestRead::TestRead(std::vector<uint8_t> data)
    : data(data)
{
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

void TestRead::start()
{
    printf("TestRead started bytes=%i\n", (int)data.size());
    //for(size_t i=0; i<crcCalculated.size(); i++)
    //    printf("TestRead CRC%i=%x\n", (int)i, (int)crcCalculated[i]);
    top->read_strobe = 1;
    top->sd_data = 0xF;
    top->data_count = data.size();

    prev_sd_clock = top->sd_clock;
}

void TestRead::beforeEval()
{
    if(clockFalling())
        return;

    if(prev_sd_clock==0 && top->sd_clock==1)
    {
        switch(state)
        {
        case State::Starting:
            {
                top->sd_data = 0xF;
                state = State::WriteZero;
                break;
            }
        case State::WriteZero:
            {
                top->sd_data = 0;
                state = State::WriteData;
                break;
            }
        case State::WriteData:
            {
                uint8_t d = data[currentIndexX2/2];
                if(currentIndexX2&1)
                    top->sd_data = d&0xF;
                else
                    top->sd_data = (d>>4)&0xF;
                currentIndexX2++;

                if(currentIndexX2/2==data.size())
                    state = State::WriteCRC;
                break;
            }
        case State::WriteCRC:
            {
                int offset = 15-crcWriteIdx;

                uint8_t p = 0;
                for(int i=0; i<4; i++)
                {
                    uint8_t d = (crcCalculated[i]>>offset)&1;
                    //uint8_t d = (crcCalculated[0]>>offset)&1;
                    p |= (d<<i);
                }

                top->sd_data = p;

                crcWriteIdx++;
                if(crcWriteIdx==16)
                    state = State::WriteOne;
                break;
            }
        case State::WriteOne:
            {
                top->sd_data = 0xF;
                state = State::Complete;
                break;
            }
        case State::Complete:
            {
                break;
            }
        }
    }

}

bool TestRead::afterEval()
{
    if(_fail)
        return false;

    if(!clockRising())
        return true;

    top->read_strobe = 0;
    prev_sd_clock = top->sd_clock;

    if(top->write_byte_strobe)
    {
        dataReceived.push_back(top->byte_out);
        if(dataReceived.size()>data.size())
        {
            printf("TestRead too many data size=%i\n", (int)dataReceived.size());
            _fail = true;
            return false;
        } else
        {
            size_t idx = dataReceived.size()-1;
            if(dataReceived[idx]!=data[idx])
            {
                printf("TestRead idx=%i received=%x original=%x\n", (int)idx, (int)dataReceived[idx], (int)data[idx]);
                _fail = true;
                return false;
            }

        }
    }

    if(top->write_all_strobe)
    {
        writeAllFound = true;
        if(dataReceived.size()!=data.size())
        {
            printf("TestRead complete not equal size received=%i original=%i\n", (int)dataReceived.size(), (int)data.size());
            _fail = true;
            return false;
        }

        if(top->crc_ok!=1)
        {
            printf("TestRead bad CRC\n");
            _fail = true;
        }
    }

    if(state==State::Complete)
    {
        if(waitAterWrite==0)
        {
            if(!writeAllFound)
            {
                printf("TestRead writeAllFound==false\n");
                _fail = true;
            }

            return false;
        }

        waitAterWrite--;
    }

    return true;
}
