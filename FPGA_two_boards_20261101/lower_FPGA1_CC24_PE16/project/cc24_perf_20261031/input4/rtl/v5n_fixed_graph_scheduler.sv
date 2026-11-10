// A2 own147 execution rows, generated from classic v5 graph; not E2E qualification.
// Frozen YOLOv8n-320/VOC4 execution sequencer.
//
// This scheduler intentionally has no descriptor configuration or loader port.
// Its 165 transactions are compiled from the frozen Round3 V2 graph map at build time.
// A layer advances only after the bound execution service reports completion;
// there is no counter/timer completion path.
module v5n_fixed_graph_scheduler #(
    // Ten minutes at 100 MHz. Override with a small value in watchdog tests.
    parameter [47:0] WATCHDOG_CYCLES = 48'd60000000000
) (
    input wire clk_i, input wire rst_ni, input wire start_i,
    output wire operation_start_o, output wire operation_valid_o,
    output wire [7:0] operation_node_id_o, output wire [3:0] operation_opcode_o,
    output wire [2:0] operation_source_count_o, output wire [31:0] operation_sources_o,
    output wire [7:0] operation_destination_o,
    output wire [9:0] operation_input_h_o, output wire [9:0] operation_input_w_o, output wire [9:0] operation_input_c_o,
    output wire [9:0] operation_output_h_o, output wire [9:0] operation_output_w_o, output wire [9:0] operation_output_c_o,
    output wire [3:0] operation_kernel_h_o, output wire [3:0] operation_kernel_w_o,
    output wire [3:0] operation_stride_h_o, output wire [3:0] operation_stride_w_o,
    output wire [3:0] operation_pad_top_o, output wire [3:0] operation_pad_left_o,
    output wire [3:0] operation_dilation_h_o, output wire [7:0] operation_groups_o,
    output wire [31:0] operation_weight_offset_o, output wire [31:0] operation_weight_bytes_o,
    output wire [31:0] operation_bias_offset_o, output wire [31:0] operation_bias_bytes_o,
    output wire [31:0] operation_requant_offset_o, output wire [31:0] operation_requant_bytes_o,
    output wire [31:0] operation_lut_offset_o, output wire [31:0] operation_lut_bytes_o,
    output wire [5:0] operation_conv_shift_o, output wire signed [127:0] operation_source_multiplier_o,
    output wire [23:0] operation_source_shift_o, output wire [39:0] operation_source_channels_o,
    output wire [7:0] operation_split_index_o, output wire [7:0] operation_detect_stride_o,
    output wire signed [7:0] operation_output_zero_point_o,
    input wire operation_accept_i, input wire operation_done_i, input wire operation_error_i,
    output wire busy_o, output reg done_o, output reg error_o, output wire [7:0] active_layer_o,
    output wire [1:0] state_o,output wire [47:0] layer_cycle_count_o,
    output wire [47:0] total_cycle_count_o,output reg watchdog_timeout_o
);
    localparam [1:0] ST_IDLE = 2'd0, ST_ISSUE = 2'd1, ST_WAIT = 2'd2, ST_DONE = 2'd3;
    reg [1:0] state_r; reg [7:0] layer_index_r;
    reg [47:0] layer_cycle_count_r,total_cycle_count_r;
    reg fixed_valid_r; reg [3:0] fixed_opcode_r; reg [2:0] fixed_source_count_r;
    reg [31:0] fixed_sources_r; reg [7:0] fixed_destination_r;
    reg [9:0] fixed_input_h_r, fixed_input_w_r, fixed_input_c_r, fixed_output_h_r, fixed_output_w_r, fixed_output_c_r;
    reg [3:0] fixed_kernel_h_r, fixed_kernel_w_r, fixed_stride_h_r, fixed_stride_w_r, fixed_pad_top_r, fixed_pad_left_r, fixed_dilation_h_r;
    reg [7:0] fixed_groups_r; reg [31:0] fixed_weight_offset_r, fixed_weight_bytes_r, fixed_bias_offset_r, fixed_bias_bytes_r;
    reg [31:0] fixed_requant_offset_r, fixed_requant_bytes_r, fixed_lut_offset_r, fixed_lut_bytes_r;
    reg [5:0] fixed_conv_shift_r; reg signed [127:0] fixed_source_multiplier_r; reg [23:0] fixed_source_shift_r;
    reg [39:0] fixed_source_channels_r; reg [7:0] fixed_split_index_r, fixed_detect_stride_r; reg signed [7:0] fixed_output_zero_point_r;

    // Frozen descriptors, no model math/weights/quantization change.
    // Prefetch the address selected by this edge's original state transition.
    // ROM output is meaningful for issue/wait; idle/reset values are not consumed.
    wire [7:0] descriptor_address = (state_r==ST_IDLE && start_i) ? 8'd0 :
      (state_r==ST_WAIT && operation_done_i && !operation_error_i &&
       layer_cycle_count_r<WATCHDOG_CYCLES-1'b1 && layer_index_r<8'd146) ?
       layer_index_r+1'b1 : layer_index_r;
    (* ram_style="bram" *) reg [199:0] descriptor_rom[0:255];
    reg [199:0] descriptor_q;
    initial begin
      descriptor_rom[0]=200'h0000000000000000000000000000000481c5001a0007ffff01;
      descriptor_rom[1]=200'h04000000000000c00000400001b0000b0422801a000fff0023;
      descriptor_rom[2]=200'h00000000000000080000000000000004842280250017ff0125;
      descriptor_rom[3]=200'h00000000000000c0001080080480037988014025001fff0223;
      descriptor_rom[4]=200'h00000000000000082000000000000004880140428027ff0325;
      descriptor_rom[5]=200'h00000000000000c00010401800800c6484014042802fff0423;
      descriptor_rom[6]=200'h00000000000000084000000000000004840140228037ff0525;
      descriptor_rom[7]=200'h00000000000000c00020402000400d6484014022803fff0623;
      descriptor_rom[8]=200'h00000000000000086000000000000004840140228047ff0725;
      descriptor_rom[9]=200'h00000000000000c00030402802400df584014022804fff0823;
      descriptor_rom[10]=200'h00000000000000088000000000000004840140228057ff0925;
      descriptor_rom[11]=200'h0ada351240603900000000000000000484014022805f0a0649;
      descriptor_rom[12]=200'h00000000000000c00020403000801264840140428067ff0423;
      descriptor_rom[13]=200'h0000000000000008a00000000000000484014022806fff0c25;
      descriptor_rom[14]=200'h0afc1b6d8000000000000000000000048801402280770d0b4b;
      descriptor_rom[15]=200'h00000000000000c0003080380100136488014042807fff0e23;
      descriptor_rom[16]=200'h0000000000000008c000000000000004880140428087ff0f25;
      descriptor_rom[17]=200'h00000000000000c000110048120015799030a042808fff1023;
      descriptor_rom[18]=200'h0000000000000008e0000000000000049030a0814097ff1125;
      descriptor_rom[19]=200'h00000000000000c000308068020039648830a081409fff1223;
      descriptor_rom[20]=200'h000000000000000900000000000000048830a04140a7ff1325;
      descriptor_rom[21]=200'h00000000000000b00030807801003d648830a04140afff1423;
      descriptor_rom[22]=200'h000000000000000920000000000000048830a04140b7ff1525;
      descriptor_rom[23]=200'h00000000000000c00050808809003f758830a04140bfff1623;
      descriptor_rom[24]=200'h000000000000000940000000000000048830a04140c7ff1725;
      descriptor_rom[25]=200'h12dfd55f40a7810000000000000000048830a04140cf181449;
      descriptor_rom[26]=200'h00000000000000c000508098010051648830a04140d7ff1923;
      descriptor_rom[27]=200'h000000000000000960000000000000048830a04140dfff1a25;
      descriptor_rom[28]=200'h00000000000000c0007080a8090053758830a04140e7ff1b23;
      descriptor_rom[29]=200'h000000000000000980000000000000048830a04140efff1c25;
      descriptor_rom[30]=200'h12d6610b6365610000000000000000048830a04140f71d1949;
      descriptor_rom[31]=200'h00000000000000c0007080b8020065648830a08140ffff1223;
      descriptor_rom[32]=200'h0000000000000009a0000000000000048830a0414107ff1f25;
      descriptor_rom[33]=200'h12b1ecf18000000000000000000000049030a041410f201e4b;
      descriptor_rom[34]=200'h00000000000000c0005100c8040069649030a0814117ff2123;
      descriptor_rom[35]=200'h0000000000000009c0000000000000049030a081411fff2225;
      descriptor_rom[36]=200'h00000000000000c0007200e848007179a00850814127ff2323;
      descriptor_rom[37]=200'h0000000000000009e000000000000004a0085100a12fff2425;
      descriptor_rom[38]=200'h00000000000000c000b101280801016490085100a137ff2523;
      descriptor_rom[39]=200'h000000000000000a000000000000000490085080a13fff2625;
      descriptor_rom[40]=200'h00000000000000c0009101480401116490085080a147ff2723;
      descriptor_rom[41]=200'h000000000000000a200000000000000490085080a14fff2825;
      descriptor_rom[42]=200'h00000000000000c000b101682401197590085080a157ff2923;
      descriptor_rom[43]=200'h000000000000000a400000000000000490085080a15fff2a25;
      descriptor_rom[44]=200'h22ecaa7f39c15e00000000000000000490085080a1672b2749;
      descriptor_rom[45]=200'h00000000000000c000d101880401616490085080a16fff2c23;
      descriptor_rom[46]=200'h000000000000000a600000000000000490085080a177ff2d25;
      descriptor_rom[47]=200'h00000000000000c000f101a82401697590085080a17fff2e23;
      descriptor_rom[48]=200'h000000000000000a800000000000000490085080a187ff2f25;
      descriptor_rom[49]=200'h22cb10503c2bfd00000000000000000490085080a18f302c49;
      descriptor_rom[50]=200'h00000000000000c000d101c80401b16490085080a197ff3123;
      descriptor_rom[51]=200'h000000000000000aa00000000000000490085080a19fff3225;
      descriptor_rom[52]=200'h00000000000000c000f101e82401b97590085080a1a7ff3323;
      descriptor_rom[53]=200'h000000000000000ac00000000000000490085080a1afff3425;
      descriptor_rom[54]=200'h22e1cc11727ec200000000000000000490085080a1b7353149;
      descriptor_rom[55]=200'h00000000000000c0011102080802016490085100a1bfff2523;
      descriptor_rom[56]=200'h000000000000000ae00000000000000490085080a1c7ff3725;
      descriptor_rom[57]=200'h22c48e91800000000000000000000004a0085080a1cf38364b;
      descriptor_rom[58]=200'h00000000000000c00132022810021164a0085100a1d7ff3923;
      descriptor_rom[59]=200'h000000000000000b0000000000000004a0085100a1dfff3a25;
      descriptor_rom[60]=200'h00000000000000c00134026920023179c0102900a1e7ff3b23;
      descriptor_rom[61]=200'h000000000000000b2000000000000004c0102a0051efff3c25;
      descriptor_rom[62]=200'h00000000000000c0017202e820047164a0102a0051f7ff3d23;
      descriptor_rom[63]=200'h000000000000000b4000000000000004a010290051ffff3e25;
      descriptor_rom[64]=200'h00000000000000c001b203281004b164a01029005207ff3f23;
      descriptor_rom[65]=200'h000000000000000b6000000000000004a0102900520fff4025;
      descriptor_rom[66]=200'h00000000000000c001b203689004d175a01029005217ff4123;
      descriptor_rom[67]=200'h000000000000000b8000000000000004a0102900521fff4225;
      descriptor_rom[68]=200'h42ff43c0322176000000000000000004a01029005227433f49;
      descriptor_rom[69]=200'h00000000000000c001f203a82005f164a0102a00522fff3d23;
      descriptor_rom[70]=200'h000000000000000ba000000000000004a01029005237ff4525;
      descriptor_rom[71]=200'h42b94b84800000000000000000000004c0102900523f46444b;
      descriptor_rom[72]=200'h00000000000000c001f403e840063164c0102a005247ff4723;
      descriptor_rom[73]=200'h000000000000000bc000000000000004c0102a00524fff4825;
      descriptor_rom[74]=200'h00000000000000c0023204682006b164a0102a005257ff4923;
      descriptor_rom[75]=200'h000000000000000be000000000000004a0102900525fff4a25;
      descriptor_rom[76]=200'h00000000000000000000000000000006a01029005267ff4b2d;
      descriptor_rom[77]=200'h00000000000000000000000000000006a0102900526fff4c2d;
      descriptor_rom[78]=200'h00000000000000000000000000000006a01029005277ff4d2d;
      descriptor_rom[79]=200'h4300000080000000000000000000000480102900527a4c4b8b;
      descriptor_rom[80]=200'h00000000000000b0027404a88006f164c0102c005287ff4f23;
      descriptor_rom[81]=200'h000000000000000c0000000000000004c0102a00528fff5025;
      descriptor_rom[82]=200'h00000000000000c002b205282007f164a0102a005297ff5123;
      descriptor_rom[83]=200'h000000000000000c2000000000000004a0102900529fff5225;
      descriptor_rom[84]=200'h00000000000000000000000000000004a008510052a7ff532f;
      descriptor_rom[85]=200'h42c16acc800000000000000000000004c0085100a2af3b544b;
      descriptor_rom[86]=200'h00000000000000c002b105681008316490085200a2b7ff5523;
      descriptor_rom[87]=200'h000000000000000c400000000000000490085080a2bfff5625;
      descriptor_rom[88]=200'h00000000000000c002d105880408516490085080a2c7ff5723;
      descriptor_rom[89]=200'h000000000000000c600000000000000490085080a2cfff5825;
      descriptor_rom[90]=200'h00000000000000c002f105a82408597590085080a2d7ff5923;
      descriptor_rom[91]=200'h000000000000000c800000000000000490085080a2dfff5a25;
      descriptor_rom[92]=200'h00000000000000c002d105c81008a16490085200a2e7ff5523;
      descriptor_rom[93]=200'h000000000000000ca00000000000000490085080a2efff5c25;
      descriptor_rom[94]=200'h22fb2673800000000000000000000004a0085080a2f75d5b4b;
      descriptor_rom[95]=200'h00000000000000c002f205e81008c164a0085100a2ffff5e23;
      descriptor_rom[96]=200'h000000000000000cc000000000000004a0085100a307ff5f25;
      descriptor_rom[97]=200'h00000000000000c0033106280808e16490085100a30fff6023;
      descriptor_rom[98]=200'h000000000000000ce00000000000000490085080a317ff6125;
      descriptor_rom[99]=200'h000000000000000000000000000000049030a080a31fff622f;
      descriptor_rom[100]=200'h22c6b00c800000000000000000000004a030a081432723634b;
      descriptor_rom[101]=200'h00000000000000c0031086480408f1648830a101432fff6423;
      descriptor_rom[102]=200'h000000000000000d00000000000000048830a0414337ff6525;
      descriptor_rom[103]=200'h00000000000000c0031086580108f9648830a041433fff6623;
      descriptor_rom[104]=200'h000000000000000d20000000000000048830a0414347ff6725;
      descriptor_rom[105]=200'h00000000000000c0033086680908fb758830a041434fff6823;
      descriptor_rom[106]=200'h000000000000000d40000000000000048830a0414357ff6925;
      descriptor_rom[107]=200'h00000000000000c00330867804090d648830a101435fff6423;
      descriptor_rom[108]=200'h000000000000000d60000000000000048830a0414367ff6b25;
      descriptor_rom[109]=200'h12f5759e8000000000000000000000049030a041436f6c6a4b;
      descriptor_rom[110]=200'h00000000000000a003510688040915649030a0814377ff6d23;
      descriptor_rom[111]=200'h000000000000000d80000000000000049030a081437fff6e25;
      descriptor_rom[112]=200'h00000000000000c0037106a824091d79900850814387ff6f23;
      descriptor_rom[113]=200'h000000000000000da00000000000000490085080a38fff7025;
      descriptor_rom[114]=200'h230000007c5a28000000000000000004a0085080a39762714b;
      descriptor_rom[115]=200'h00000000000000c0035106c80809656490085100a39fff7223;
      descriptor_rom[116]=200'h000000000000000dc00000000000000490085080a3a7ff7325;
      descriptor_rom[117]=200'h00000000000000c0037106e80409756490085080a3afff7423;
      descriptor_rom[118]=200'h000000000000000de00000000000000490085080a3b7ff7525;
      descriptor_rom[119]=200'h00000000000000c00391070824097d7590085080a3bfff7623;
      descriptor_rom[120]=200'h000000000000000e000000000000000490085080a3c7ff7725;
      descriptor_rom[121]=200'h00000000000000c003b107280809c56490085100a3cfff7223;
      descriptor_rom[122]=200'h000000000000000e200000000000000490085080a3d7ff7925;
      descriptor_rom[123]=200'h22d78ea3800000000000000000000004a0085080a3df7a784b;
      descriptor_rom[124]=200'h00000000000000c0039207481009d564a0085100a3e7ff7b23;
      descriptor_rom[125]=200'h000000000000000e4000000000000004a0085100a3efff7c25;
      descriptor_rom[126]=200'h00000000000000c003d207889009f579a0102900a3f7ff7d23;
      descriptor_rom[127]=200'h000000000000000e6000000000000004a010290053ffff7e25;
      descriptor_rom[128]=200'h42e336c4800000000000000000000004c01029005407537f4b;
      descriptor_rom[129]=200'h00000000000000c003d207c8200b1564a0102a00540fff8023;
      descriptor_rom[130]=200'h000000000000000e8000000000000004a01029005417ff8125;
      descriptor_rom[131]=200'h00000000000000c004120808100b5564a0102900541fff8223;
      descriptor_rom[132]=200'h000000000000000ea000000000000004a01029005427ff8325;
      descriptor_rom[133]=200'h00000000000000c004120848900b7575a0102900542fff8423;
      descriptor_rom[134]=200'h000000000000000ec000000000000004a01029005437ff8525;
      descriptor_rom[135]=200'h00000000000000c004520888200c9564a0102a00543fff8023;
      descriptor_rom[136]=200'h000000000000000ee000000000000004a01029005447ff8725;
      descriptor_rom[137]=200'h42d028fb800000000000000000000004c0102900544f88864b;
      descriptor_rom[138]=200'h00000000000000c0045408c8400cd564c0102a005457ff8923;
      descriptor_rom[139]=200'h000000000000000f0000000000000004c0102a00545fff8a25;
      descriptor_rom[140]=200'h00000000000000c00490594801bd556487b0a0814467ff6f23;
      descriptor_rom[141]=200'h00000000000000c004885956036d58c487885100a46fff7d23;
      descriptor_rom[142]=200'h00000000000000c004a8596406cd5f8487902a005477ff8b23;
      descriptor_rom[143]=200'h8400000000000007200027a0000000048230a031447fff8c31;
      descriptor_rom[144]=200'h0400000000000007a80028240000000482085030a487ff8d31;
      descriptor_rom[145]=200'h0400000000000000300028a80000000482102830548fff8e31;
      descriptor_rom[146]=200'h000000000000000000000000000000048104b0000c94908f73;
      descriptor_rom[147]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[148]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[149]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[150]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[151]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[152]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[153]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[154]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[155]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[156]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[157]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[158]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[159]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[160]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[161]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[162]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[163]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[164]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[165]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[166]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[167]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[168]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[169]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[170]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[171]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[172]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[173]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[174]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[175]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[176]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[177]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[178]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[179]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[180]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[181]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[182]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[183]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[184]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[185]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[186]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[187]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[188]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[189]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[190]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[191]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[192]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[193]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[194]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[195]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[196]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[197]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[198]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[199]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[200]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[201]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[202]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[203]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[204]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[205]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[206]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[207]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[208]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[209]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[210]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[211]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[212]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[213]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[214]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[215]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[216]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[217]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[218]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[219]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[220]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[221]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[222]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[223]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[224]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[225]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[226]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[227]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[228]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[229]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[230]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[231]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[232]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[233]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[234]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[235]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[236]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[237]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[238]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[239]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[240]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[241]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[242]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[243]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[244]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[245]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[246]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[247]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[248]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[249]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[250]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[251]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[252]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[253]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[254]=200'h00000000000000000000000000000000000000000000000000;
      descriptor_rom[255]=200'h00000000000000000000000000000000000000000000000000;
    end
    always @(posedge clk_i) descriptor_q<=descriptor_rom[descriptor_address];
    always @* begin
      fixed_valid_r={descriptor_q[0]};
      fixed_opcode_r={descriptor_q[4],descriptor_q[3],descriptor_q[2],descriptor_q[1]};
      fixed_source_count_r={descriptor_q[7],descriptor_q[6],descriptor_q[5]};
      fixed_sources_r={descriptor_q[26],descriptor_q[0],descriptor_q[26],descriptor_q[26],descriptor_q[0],descriptor_q[0],descriptor_q[0],descriptor_q[26],descriptor_q[26],descriptor_q[25],descriptor_q[24],descriptor_q[26],descriptor_q[25],descriptor_q[25],descriptor_q[24],descriptor_q[0],descriptor_q[23],descriptor_q[22],descriptor_q[21],descriptor_q[20],descriptor_q[19],descriptor_q[18],descriptor_q[17],descriptor_q[16],descriptor_q[15],descriptor_q[14],descriptor_q[13],descriptor_q[12],descriptor_q[11],descriptor_q[10],descriptor_q[9],descriptor_q[8]};
      fixed_destination_r={descriptor_q[34],descriptor_q[33],descriptor_q[32],descriptor_q[31],descriptor_q[30],descriptor_q[29],descriptor_q[28],descriptor_q[27]};
      fixed_input_h_r={1'b0,descriptor_q[43],descriptor_q[42],descriptor_q[41],descriptor_q[40],descriptor_q[39],descriptor_q[38],descriptor_q[37],descriptor_q[36],descriptor_q[35]};
      fixed_input_w_r={1'b0,descriptor_q[43],descriptor_q[42],descriptor_q[41],descriptor_q[40],descriptor_q[39],descriptor_q[38],descriptor_q[37],descriptor_q[36],descriptor_q[35]};
      fixed_input_c_r={descriptor_q[50],descriptor_q[49],descriptor_q[48],descriptor_q[47],descriptor_q[46],descriptor_q[45],descriptor_q[4],1'b0,descriptor_q[44],descriptor_q[44]};
      fixed_output_h_r={1'b0,descriptor_q[58],descriptor_q[57],descriptor_q[56],descriptor_q[55],descriptor_q[54],descriptor_q[53],descriptor_q[52],descriptor_q[51],1'b0};
      fixed_output_w_r={1'b0,descriptor_q[62],descriptor_q[57],descriptor_q[56],descriptor_q[61],descriptor_q[54],descriptor_q[60],descriptor_q[59],descriptor_q[51],descriptor_q[35]};
      fixed_output_c_r={descriptor_q[7],descriptor_q[70],descriptor_q[69],descriptor_q[68],descriptor_q[67],descriptor_q[66],descriptor_q[65],descriptor_q[35],descriptor_q[64],descriptor_q[63]};
      fixed_kernel_h_r={1'b0,descriptor_q[73],descriptor_q[72],descriptor_q[71]};
      fixed_kernel_w_r={1'b0,descriptor_q[73],descriptor_q[72],descriptor_q[71]};
      fixed_stride_h_r={1'b0,1'b0,descriptor_q[75],descriptor_q[74]};
      fixed_stride_w_r={1'b0,1'b0,descriptor_q[75],descriptor_q[74]};
      fixed_pad_top_r={1'b0,1'b0,descriptor_q[73],descriptor_q[76]};
      fixed_pad_left_r={1'b0,1'b0,descriptor_q[73],descriptor_q[76]};
      fixed_dilation_h_r={1'b0,1'b0,1'b0,descriptor_q[0]};
      fixed_groups_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[0]};
      fixed_weight_offset_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[91],descriptor_q[90],descriptor_q[89],descriptor_q[88],descriptor_q[87],descriptor_q[86],descriptor_q[85],descriptor_q[84],descriptor_q[83],descriptor_q[82],descriptor_q[81],descriptor_q[80],descriptor_q[79],descriptor_q[78],descriptor_q[77],1'b0,1'b0,1'b0,1'b0,1'b0,1'b0};
      fixed_weight_bytes_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[104],descriptor_q[103],descriptor_q[102],descriptor_q[101],descriptor_q[100],descriptor_q[99],descriptor_q[98],descriptor_q[97],descriptor_q[96],descriptor_q[95],descriptor_q[94],descriptor_q[93],descriptor_q[92],1'b0,1'b0,1'b0,1'b0,1'b0,1'b0};
      fixed_bias_offset_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[115],descriptor_q[114],descriptor_q[113],descriptor_q[112],descriptor_q[111],descriptor_q[110],descriptor_q[109],descriptor_q[108],descriptor_q[107],descriptor_q[106],descriptor_q[105],1'b0,1'b0,1'b0,1'b0};
      fixed_bias_bytes_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[122],descriptor_q[121],descriptor_q[120],descriptor_q[119],descriptor_q[118],descriptor_q[116],descriptor_q[117],descriptor_q[65],descriptor_q[116],1'b0,1'b0};
      fixed_requant_offset_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[130],descriptor_q[129],descriptor_q[128],descriptor_q[127],descriptor_q[126],descriptor_q[110],descriptor_q[125],descriptor_q[108],descriptor_q[124],descriptor_q[123],descriptor_q[105],1'b0,1'b0,1'b0,1'b0};
      fixed_requant_bytes_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[122],descriptor_q[121],descriptor_q[120],descriptor_q[119],descriptor_q[118],descriptor_q[116],1'b0,descriptor_q[116],descriptor_q[116],1'b0,1'b0};
      fixed_lut_offset_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[132],descriptor_q[138],descriptor_q[137],descriptor_q[136],descriptor_q[135],descriptor_q[134],descriptor_q[133],1'b0,descriptor_q[132],descriptor_q[131],1'b0,1'b0,1'b0,1'b0,1'b0};
      fixed_lut_bytes_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[117],1'b0,descriptor_q[139],1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0};
      fixed_conv_shift_r={1'b0,descriptor_q[143],descriptor_q[142],descriptor_q[141],descriptor_q[141],descriptor_q[140]};
      fixed_source_multiplier_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[7],1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[7],1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[192],descriptor_q[191],descriptor_q[190],descriptor_q[189],descriptor_q[188],descriptor_q[187],descriptor_q[186],descriptor_q[185],descriptor_q[184],descriptor_q[183],descriptor_q[182],descriptor_q[181],descriptor_q[180],descriptor_q[179],descriptor_q[178],descriptor_q[177],descriptor_q[176],descriptor_q[175],descriptor_q[174],descriptor_q[173],descriptor_q[172],descriptor_q[171],descriptor_q[170],descriptor_q[169],descriptor_q[168],1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[167],descriptor_q[166],descriptor_q[147],descriptor_q[165],descriptor_q[164],descriptor_q[163],descriptor_q[162],descriptor_q[161],descriptor_q[160],descriptor_q[159],descriptor_q[158],descriptor_q[157],descriptor_q[156],descriptor_q[155],descriptor_q[154],descriptor_q[153],descriptor_q[152],descriptor_q[151],descriptor_q[150],descriptor_q[149],descriptor_q[148],descriptor_q[147],descriptor_q[146],descriptor_q[145],descriptor_q[144]};
      fixed_source_shift_r={1'b0,descriptor_q[7],descriptor_q[7],1'b0,1'b0,1'b0,1'b0,descriptor_q[7],descriptor_q[7],1'b0,1'b0,1'b0,1'b0,descriptor_q[193],descriptor_q[193],1'b0,1'b0,1'b0,1'b0,descriptor_q[193],descriptor_q[193],1'b0,1'b0,1'b0};
      fixed_source_channels_r={1'b0,1'b0,descriptor_q[7],1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[7],1'b0,1'b0,1'b0,descriptor_q[35],1'b0,1'b0,1'b0,1'b0,1'b0,descriptor_q[198],descriptor_q[197],descriptor_q[196],descriptor_q[195],descriptor_q[35],1'b0,1'b0,1'b0,descriptor_q[50],descriptor_q[49],descriptor_q[48],descriptor_q[47],descriptor_q[46],descriptor_q[45],descriptor_q[4],1'b0,descriptor_q[194],descriptor_q[194]};
      fixed_split_index_r={descriptor_q[0],descriptor_q[0],descriptor_q[0],descriptor_q[0],descriptor_q[0],descriptor_q[0],descriptor_q[0],descriptor_q[0]};
      fixed_detect_stride_r={1'b0,1'b0,descriptor_q[132],descriptor_q[131],descriptor_q[199],1'b0,1'b0,1'b0};
      fixed_output_zero_point_r={1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0};
    end

    assign operation_start_o = (state_r == ST_ISSUE);
    assign operation_valid_o = fixed_valid_r;
    assign operation_node_id_o = layer_index_r; assign operation_opcode_o = fixed_opcode_r;
    assign operation_source_count_o = fixed_source_count_r; assign operation_sources_o = fixed_sources_r; assign operation_destination_o = fixed_destination_r;
    assign operation_input_h_o = fixed_input_h_r; assign operation_input_w_o = fixed_input_w_r; assign operation_input_c_o = fixed_input_c_r;
    assign operation_output_h_o = fixed_output_h_r; assign operation_output_w_o = fixed_output_w_r; assign operation_output_c_o = fixed_output_c_r;
    assign operation_kernel_h_o = fixed_kernel_h_r; assign operation_kernel_w_o = fixed_kernel_w_r; assign operation_stride_h_o = fixed_stride_h_r; assign operation_stride_w_o = fixed_stride_w_r;
    assign operation_pad_top_o = fixed_pad_top_r; assign operation_pad_left_o = fixed_pad_left_r; assign operation_dilation_h_o = fixed_dilation_h_r; assign operation_groups_o = fixed_groups_r;
    assign operation_weight_offset_o = fixed_weight_offset_r; assign operation_weight_bytes_o = fixed_weight_bytes_r; assign operation_bias_offset_o = fixed_bias_offset_r; assign operation_bias_bytes_o = fixed_bias_bytes_r;
    assign operation_requant_offset_o = fixed_requant_offset_r; assign operation_requant_bytes_o = fixed_requant_bytes_r; assign operation_lut_offset_o = fixed_lut_offset_r; assign operation_lut_bytes_o = fixed_lut_bytes_r;
    assign operation_conv_shift_o = fixed_conv_shift_r; assign operation_source_multiplier_o = fixed_source_multiplier_r; assign operation_source_shift_o = fixed_source_shift_r; assign operation_source_channels_o = fixed_source_channels_r;
    assign operation_split_index_o = fixed_split_index_r; assign operation_detect_stride_o = fixed_detect_stride_r; assign operation_output_zero_point_o = fixed_output_zero_point_r;
    assign busy_o = (state_r == ST_ISSUE) || (state_r == ST_WAIT); assign active_layer_o = layer_index_r;
    assign state_o=state_r;assign layer_cycle_count_o=layer_cycle_count_r;assign total_cycle_count_o=total_cycle_count_r;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin state_r <= ST_IDLE; layer_index_r <= 0; done_o <= 0; error_o <= 0;
            layer_cycle_count_r<=0;total_cycle_count_r<=0;watchdog_timeout_o<=0;end
        else begin
            done_o <= 1'b0;
            if(busy_o)begin
                layer_cycle_count_r<=layer_cycle_count_r+1'b1;
                total_cycle_count_r<=total_cycle_count_r+1'b1;
            end
            case (state_r)
                ST_IDLE: if (start_i) begin layer_index_r <= 0; error_o <= 1'b0;watchdog_timeout_o<=0;
                    layer_cycle_count_r<=0;total_cycle_count_r<=0;state_r <= ST_ISSUE; end
                ST_ISSUE: if(layer_cycle_count_r>=WATCHDOG_CYCLES-1'b1)begin error_o<=1;watchdog_timeout_o<=1;state_r<=ST_IDLE;end
                    else if (!fixed_valid_r) begin error_o <= 1'b1; state_r <= ST_IDLE; end else if (operation_accept_i) state_r <= ST_WAIT;
                ST_WAIT: if(layer_cycle_count_r>=WATCHDOG_CYCLES-1'b1)begin error_o<=1;watchdog_timeout_o<=1;state_r<=ST_IDLE;end
                  else if (operation_error_i) begin error_o <= 1'b1; state_r <= ST_IDLE; end else if (operation_done_i) begin
                    if (layer_index_r == 8'd146) state_r <= ST_DONE; else begin layer_index_r <= layer_index_r + 1'b1;layer_cycle_count_r<=0; state_r <= ST_ISSUE; end
                end
                ST_DONE: begin done_o <= 1'b1; state_r <= ST_IDLE; end
                default: begin error_o <= 1'b1; state_r <= ST_IDLE; end
            endcase
        end
    end
endmodule
