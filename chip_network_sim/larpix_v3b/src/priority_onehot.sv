// File Name: priority_onehot.sv
// Engineer:  Carl Grace (crgrace@lbl.gov)
// Description:  Priority encoder used in hydra_ctrl.sv and
//               event_router.sv
///////////////////////////////////////////////////////////////////

function automatic logic [PL:0] priority_onehot (input logic [PL:0] vec);
    logic [PL:0] result;
    result = '0;
    for (int i = 0; i < PL; i++)
        if (vec[i] && result == '0) result[i] = 1'b1;
    return result;
endfunction

