// Rising-edge D flip-flop as a user-defined primitive (simulation only)
// Any change on notifier (a timing check violation) sets q to x
`timescale 1ns/1ps

primitive udp_dff (q, d, clk, notifier);
    output q;
    reg    q;
    input  d, clk, notifier;

    table
    //  d   clk   notifier  :  q  :  q+
        0   (01)  ?         :  ?  :  0;   // rising edge
        1   (01)  ?         :  ?  :  1;
        0   (0x)  ?         :  0  :  0;   // unknown edge, same value
        1   (0x)  ?         :  1  :  1;
        0   (x1)  ?         :  0  :  0;
        1   (x1)  ?         :  1  :  1;
        ?   (?0)  ?         :  ?  :  -;   // falling edge
        ?   (1x)  ?         :  ?  :  -;
        *   ?     ?         :  ?  :  -;   // d changes, clock steady
        ?   ?     *         :  ?  :  x;   // violation
    endtable
endprimitive
