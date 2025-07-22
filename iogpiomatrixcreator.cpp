#include "iogpiomatrixcreator.h"

IOGPIOMatrixCreator::IOGPIOMatrixCreator()
 //: IOGPIODPi(4, 17, 27, 22)
 : IOGPIODPi(26, 16, 21, 20)
{
    // Pin mapping (in order: TMS, TCK, TDI, TDO):
    // GPIO4  -> TMS (Mode Select)
    // GPIO17 -> TCK (Clock)
    // GPIO27 -> TDI (Data In)
    // GPIO22 -> TDO (Data Out)
}

