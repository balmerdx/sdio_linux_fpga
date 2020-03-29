#include "verilated.h"
#include <verilated_vcd_c.h>

#include "tests.h"
#include <memory>

// Current simulation time (64-bit unsigned)
vluint64_t main_time = 0;
// Called by $time in Verilog
double sc_time_stamp() {
    return main_time;  // Note does conversion to real, to match SystemC
}

int main(int argc, char** argv, char** env)
{
	Verilated::commandArgs(argc, argv);
    Vsd_read_stream* top = new Vsd_read_stream;
    // If verilator was invoked with --trace argument,
    // and if at run time passed the +trace argument, turn on tracing
    VerilatedVcdC* tfp = NULL;
    const char* flag = Verilated::commandArgsPlusMatch("trace");
    if (flag && 0==strcmp(flag, "+trace")) {
        Verilated::traceEverOn(true);  // Verilator must compute traced signals
        VL_PRINTF("Enabling waves into logs/vlt_dump.vcd...\n");
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);  // Trace 99 levels of hierarchy
        Verilated::mkdir("logs");
        tfp->open("logs/vlt_dump.vcd");  // Open the dump file
    }

	top->clock = 0;
    top->sd_clock = 0;
    top->sd_serial = 1;
    top->read_enabled = 1;

    std::vector<std::shared_ptr<VerilogTest>> test;
    test.push_back(std::make_shared<TestSilence>(20));
    test.push_back(std::make_shared<TestRead>(1));
    test.push_back(std::make_shared<TestSilence>(20));
    test.push_back(std::make_shared<TestRead>(0x3FFFFFFFFF));

    test.push_back(std::make_shared<TestRead>(0x3FFFFFFFFF, TestRead::Bad::CRC));
    test.push_back(std::make_shared<TestRead>(0x3FFFFFFFFF, TestRead::Bad::Direction));
    test.push_back(std::make_shared<TestRead>(0x3FFFFFFFFF, TestRead::Bad::EndBit));
    test.push_back(std::make_shared<TestSilence>(20));
    test.push_back(std::make_shared<TestRead>(0x1FFF));
    test.push_back(std::make_shared<TestRead>(1, TestRead::Bad::ReadDisabled));


    int current_test = -1;
    bool next_test = true;
    bool test_failed = false;

	while (!Verilated::gotFinish())
	{
        if(next_test)
        {
            current_test++;
            if(current_test>=test.size())
                break;
            next_test = false;
            test[current_test]->init(top);
            test[current_test]->start();
        }

        top->clock = (main_time&1)?1:0;
        top->sd_clock = ((main_time/4)&1)?1:0;
        test[current_test]->beforeEval();

        top->eval();
        // Dump trace data for this cycle
        if (tfp) tfp->dump (main_time);

        if(!test[current_test]->afterEval())
        {
            if(test[current_test]->fail())
            {
                printf("---- Failed\n");
                test_failed = true;
                break;
            }

            printf("---- Succeeded\n");
            next_test = true;
        }


        main_time++;  // Time passes...
    }

    if(test_failed)
        printf("Tests failed\n");
    else
        printf("All tests succeeded\n");


    // Final model cleanup
    top->final();

    // Close trace if opened
    if (tfp) { tfp->close(); tfp = NULL; }

	delete top;
    exit(test_failed?1:0);
}
