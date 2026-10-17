// 2-input XOR as a user-defined primitive (simulation only)
// Any input that is not 0 or 1 gives x
`timescale 1ns/1ps

primitive udp_xor (y, a, b);
    output y;
    input  a, b;

    table
    //  a  b  :  y
        0  0  :  0;
        0  1  :  1;
        1  0  :  1;
        1  1  :  0;
    endtable
endprimitive
