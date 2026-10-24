#include "Vtb_m2_family_apf.h"
#include "verilated.h"
#include <memory>
int main(int argc, char** argv) {
 auto ctx=std::make_unique<VerilatedContext>(); ctx->commandArgs(argc,argv);
 auto top=std::make_unique<Vtb_m2_family_apf>(ctx.get());
 while(!ctx->gotFinish()) {
  top->eval();
  if(!top->eventsPending()) break;
  ctx->time(top->nextTimeSlot());
 }
 top->final(); return ctx->gotFinish()?0:2;
}
