// Graphics Gremlin
//
// Copyright (c) 2021 Eric Schlaepfer
// This work is licensed under the Creative Commons Attribution-ShareAlike 4.0
// International License. To view a copy of this license, visit
// http://creativecommons.org/licenses/by-sa/4.0/ or send a letter to Creative
// Commons, PO Box 1866, Mountain View, CA 94042, USA.
//
`default_nettype wire
module cga(
    // Clocks
    input clk,
    output [4:0] clkdiv,

    // ISA bus
    input[14:0] bus_a,
    input bus_ior_l,
    input bus_iow_l,
    input bus_memr_l,
    input bus_memw_l,
    input[7:0] bus_d,
    output[7:0] bus_out,
    output bus_dir,
    input bus_aen,
    output bus_rdy,

    // RAM
    output ram_we_l,
    output[18:0] ram_a,
    input[7:0] ram_d,

    // Video outputs
    output hsync,
    output hblank,
    output dbl_hsync,
    output vsync,
    output vblank,
    output vblank_border,
    output std_hsyncwidth,
    output de_o,
    output[3:0] video,
    output[3:0] dbl_video,
    output[6:0] comp_video,

    input splashscreen,
    input thin_font,
    input tandy_video,
    input [1:0] pcjr_addr_mode,
    output grph_mode,
    output hres_mode,
    output tandy_color_16,
    input cga_hw,
    input[3:0] crt_h_offset,
    input[2:0] crt_v_offset
    );

    parameter MDA_70HZ = 0;
    parameter BLINK_MAX = 0;
    // `define CGA_SNOW = 1; No snow

    parameter USE_BUS_WAIT = 0; // Should we add wait states on the ISA bus?
    parameter NO_DISPLAY_DISABLE = 0; // If 1, prevents flicker artifacts in DOS
    localparam STD_HSYNCWIDTH = 4'd10;

    parameter IO_BASE_ADDR = 16'h3d0; // MDA is 3B0, CGA is 3D0
    // parameter FRAMEBUFFER_ADDR = 20'hB8000; // MDA is B0000, CGA is B8000

    wire crtc_cs;
    wire status_cs;
    wire tandy_newcolorsel_cs;
    wire colorsel_cs;
    wire control_cs;
    //wire bus_mem_cs;

    reg[7:0] bus_int_out;
    wire[7:0] bus_out_crtc;
    wire[7:0] bus_out_mem;
    wire[7:0] cga_status_reg;
    wire[7:0] pcjr_status_reg;
    reg[7:0] cga_control_reg = 8'b0010_1001; // (TEXT 80x25)
    //reg[7:0] cga_control_reg = 8'b0010_1010; // (GFX 320 x 200)
    reg[7:0] cga_color_reg = 8'b0000_0000;
    reg[7:0] tandy_color_reg = 8'b0000_0000;
    reg[3:0] tandy_bordercol = 4'b0000;
    reg[4:0] tandy_modesel = 5'b00000;
    reg       palette_write = 1'b0;
    reg [3:0] palette_index = 4'd0;
    reg [3:0] palette_value = 4'd0;

    reg [4:0] pcjr_array_index = 5'd0;
    reg       pcjr_array_ff = 1'b0;
    reg       pcjr_status_toggle = 1'b0;
    reg [7:0] pcjr_array[0:31];
    integer   pcjr_i;

    initial begin
        for (pcjr_i = 0; pcjr_i < 32; pcjr_i = pcjr_i + 1)
            pcjr_array[pcjr_i] = 8'd0;
        pcjr_array[0] = 8'h09;
        pcjr_array[1] = 8'h0F;
        pcjr_array[2] = 8'h00;
        pcjr_array[3] = 8'h02;
    end

    wire pcjr_video = tandy_video;
    wire tandy_16_mode = tandy_video;
    wire [8:0] pcjr_mode_sel = {pcjr_array[3][3], (pcjr_array[0] & 8'h13)};
    wire pcjr_mode_text = (pcjr_mode_sel == 9'h00) || (pcjr_mode_sel == 9'h01);
    wire pcjr_mode_16 = (pcjr_mode_sel == 9'h13) || (pcjr_mode_sel == 9'h12);
    wire pcjr_mode_640 = (pcjr_mode_sel == 9'h03) || (pcjr_mode_sel == 9'h102);
    wire pcjr_color_4 = (pcjr_mode_sel == 9'h03);
    wire pcjr_grph_mode = ~pcjr_mode_text;
    wire pcjr_bw_mode = pcjr_array[0][2];
    wire pcjr_hres_mode = pcjr_array[0][0];
    wire pcjr_video_enabled = pcjr_array[0][3];
    wire pcjr_blink_enabled = pcjr_array[3][2];
    wire [3:0] pcjr_palette_mask = pcjr_array[1][3:0];
    wire [3:0] pcjr_border_color = pcjr_array[2][3:0];

    wire bw_mode;
    wire mode_640;
    wire video_enabled;
    wire blink_enabled;
    wire tandy_color_4;
    wire [3:0] border_color;

    wire hsync_int;
    wire vsync_l;
    wire cursor;
    wire display_enable;
    wire [3:0] hsync_width_crtc;

    // Two different clocks from the sequencer
    wire hclk;
    wire lclk;

    wire[13:0] crtc_addr;
    wire[4:0] row_addr;
    wire line_reset;
    wire pixel_addr13;
    wire pixel_addr14;
    wire pcjr_graphics;
    wire pcjr_addr_use;
    wire pcjr_addr_hi;

    wire charrom_read;
    wire disp_pipeline;
    wire isa_op_enable;
    wire vram_read_char;
    wire vram_read_att;
    wire vram_read;
    wire vram_read_a0;
//    wire[4:0] clkdiv;
    wire crtc_clk;
    wire[7:0] ram_1_d;

    reg[23:0] blink_counter = 24'd0;
    reg blink = 0;     

    reg bus_memw_synced_l;
    reg bus_memr_synced_l;
    reg bus_ior_synced_l;
    reg bus_iow_synced_l;
    reg prev_bus_ior_synced_l;
    reg prev_bus_iow_synced_l;
    wire bus_ior_pulse;
    wire bus_iow_pulse;

    //wire cpu_memsel;
    //reg[1:0] wait_state = 2'd0;
    //reg bus_rdy_latch; 

    assign de_o = display_enable;
    
    assign ram_a = {4'h0, pixel_addr14, pixel_addr13, crtc_addr[11:0],
                    vram_read_a0};

    assign ram_1_d = ram_d;
    //assign ram_1_d = 8'hFF;
    assign ram_we_l = vram_read;
    

    // Synchronize ISA bus control lines to our clock
    always @ (posedge clk)
    begin
        //bus_memw_synced_l <= bus_memw_l;
        //bus_memr_synced_l <= bus_memr_l;
        bus_ior_synced_l <= bus_ior_l;
        bus_iow_synced_l <= bus_iow_l;
        prev_bus_ior_synced_l <= bus_ior_synced_l;
        prev_bus_iow_synced_l <= bus_iow_synced_l;
    end

    assign bus_ior_pulse = ~bus_ior_synced_l & prev_bus_ior_synced_l;
    assign bus_iow_pulse = ~bus_iow_synced_l & prev_bus_iow_synced_l;

    // Some modules need a non-inverted vsync trigger
    assign vsync = ~vsync_l;

    // Mapped IO
    assign crtc_cs = (bus_a[14:3] == IO_BASE_ADDR[14:3]) & ~bus_aen & cga_hw; // 3D4/3D5
    assign status_cs = (bus_a == IO_BASE_ADDR + 20'hA) & ~bus_aen & cga_hw;
    assign tandy_newcolorsel_cs = (bus_a == IO_BASE_ADDR + 20'hE) & ~bus_aen & cga_hw;
    assign control_cs = (bus_a == IO_BASE_ADDR + 16'h8) & ~bus_aen & cga_hw;
    assign colorsel_cs = (bus_a == IO_BASE_ADDR + 20'h9) & ~bus_aen & cga_hw;
    // Memory-mapped from B0000 to B7FFF
    //assign bus_mem_cs = (bus_a[19:15] == FRAMEBUFFER_ADDR[19:15]);
    //assign bus_mem_cs = 1'b1;


    // Mux ISA bus data from every possible internal source.
    always @ (*)
    begin
//        if (bus_mem_cs & ~bus_memr_l) begin
//            bus_int_out <= bus_out_mem;
        if (status_cs & ~bus_ior_l) begin
            bus_int_out <= pcjr_video ? pcjr_status_reg : cga_status_reg;
        end else if (crtc_cs & ~bus_ior_l & (bus_a[0] == 1)) begin
            bus_int_out <= bus_out_crtc;
        end else begin
            bus_int_out <= 8'h00;
        end
    end

    // Only for read operations does bus_dir go high.
    assign bus_dir = (crtc_cs | status_cs) & ~bus_ior_l;
    //                | (bus_mem_cs & ~bus_memr_l);
    //assign bus_dir = (crtc_cs | status_cs);
    assign bus_out = bus_int_out;

    // Wait state generator
    // Optional for operation but required to run timing-sensitive demos
    // e.g. 8088MPH.
    /*
    if (USE_BUS_WAIT == 0) begin
        assign bus_rdy = 1;
    end else begin
        assign bus_rdy = bus_rdy_latch;
    end
    */

/*
    assign cpu_memsel = bus_mem_cs & (~bus_memr_l | ~bus_memw_l);

    always @ (posedge clk)
    begin
        if (cpu_memsel) begin
            case (wait_state)
                2'b00: begin
                    if (clkdiv == 5'd17) wait_state <= 2'b01;
                    bus_rdy_latch <= 0;
                end
                2'b01: begin
                    if (clkdiv == 5'd20) wait_state <= 2'b10;
                    bus_rdy_latch <= 0;
                end
                2'b10: begin
                    wait_state <= 2'b10;
                    bus_rdy_latch <= 1;
                end
                default: begin
                    wait_state <= 2'b00;
                    bus_rdy_latch <= 0;
                end
            endcase
        end else begin
            wait_state <= 2'b00;
            bus_rdy_latch <= 1;
        end
    end
*/

    // status register (read only at 3BA)
    // FIXME: vsync_l should be delayed/synced to HCLK.
    assign cga_status_reg = {4'b1111, vsync_l, 2'b10, ~display_enable};
    assign pcjr_status_reg = {3'b000, pcjr_status_toggle, vsync_l, 2'b00, display_enable};

    // mode control register (write only)
    //
    assign hres_mode = pcjr_video ? pcjr_hres_mode : cga_control_reg[0]; // 1=80x25,0=40x25
    assign grph_mode = pcjr_video ? pcjr_grph_mode : cga_control_reg[1]; // 1=graphics, 0=text
    assign bw_mode = pcjr_video ? pcjr_bw_mode : cga_control_reg[2]; // 1=b&w, 0=color

    assign video_enabled = pcjr_video ? pcjr_video_enabled :
        (NO_DISPLAY_DISABLE ? 1'b1 : cga_control_reg[3]);
     
    assign mode_640 = pcjr_video ? pcjr_mode_640 : cga_control_reg[4]; // 1=640x200 mode, 0=others
    assign blink_enabled = pcjr_video ? pcjr_blink_enabled : cga_control_reg[5];
	 
    assign tandy_color_16 = pcjr_video ? pcjr_mode_16 : tandy_modesel[4];
    assign tandy_color_4 = pcjr_video ? pcjr_color_4 : tandy_modesel[3];
    assign border_color = pcjr_video ? pcjr_border_color : tandy_bordercol;
    assign std_hsyncwidth = (hsync_width_crtc == STD_HSYNCWIDTH);
    assign vblank_border = vblank;

    assign hsync = hsync_int;

    // Update control or color register
    always @ (posedge clk)
    begin
        palette_write <= 1'b0;
        if (pcjr_video) begin
            if (status_cs && bus_ior_pulse) begin
                pcjr_array_ff <= 1'b0;
                pcjr_status_toggle <= ~pcjr_status_toggle;
            end
            if (status_cs && bus_iow_pulse) begin
                if (!pcjr_array_ff)
                    pcjr_array_index <= bus_d[4:0];
                else begin
                    pcjr_array[pcjr_array_index] <= pcjr_array_index[4] ? {4'b0000, bus_d[3:0]} : bus_d;
                    if (pcjr_array_index[4]) begin
                        palette_write <= 1'b1;
                        palette_index <= pcjr_array_index[3:0];
                        palette_value <= bus_d[3:0];
                    end
                end
                pcjr_array_ff <= ~pcjr_array_ff;
            end
        end else if (~bus_iow_synced_l) begin
            if (control_cs) begin
                cga_control_reg <= bus_d;
            end else if (colorsel_cs) begin
                cga_color_reg <= bus_d;
            end else if (status_cs) begin
                tandy_color_reg <= bus_d;
            end else if (tandy_newcolorsel_cs && tandy_color_reg[7:4] == 4'b0001) begin // Palette Mask Register
                palette_index <= tandy_color_reg[3:0];
                palette_value <= bus_d[3:0];
                palette_write <= 1'b1;
            end else if (tandy_newcolorsel_cs && tandy_color_reg[3:0] == 4'b0010) begin // Border Color
                tandy_bordercol <= bus_d[3:0];
            end else if (tandy_newcolorsel_cs && tandy_color_reg[3:0] == 4'b0011) begin // Mode Select
                tandy_modesel <= bus_d[4:0];
            end
        end
    end 
	 
	
    UM6845R crtc (
        .CLOCK(clk),
		  .CLKEN(crtc_clk), 
		  // .nCLKEN(),
		  .nRESET(1'b1),
		  .CRTC_TYPE(1'b1),
		  
		  .ENABLE(1'b1),
		  .nCS(~crtc_cs),
		  .R_nW(bus_iow_synced_l),
		  .RS(bus_a[0]),
		  .DI(bus_d),
		  .DO(bus_out_crtc),
		  
		  .hblank(hblank),
		  .vblank(vblank),
		  .line_reset(line_reset),
		  
		  .VSYNC(vsync_l),
		  .HSYNC(hsync_int),
		  .DE(display_enable),
		  // .FIELD(),
		  .CURSOR(cursor),
		  
		  .MA(crtc_addr),
		  .RA(row_addr),
		  .hsync_width(hsync_width_crtc),
		  
		  .crt_h_offset(crt_h_offset),
		  .crt_v_offset(crt_v_offset),
		  .hres_mode(hres_mode)
	 );

    // CGA 80 column timings
    defparam crtc.H_TOTAL = 8'd113; // 113 // 56
    defparam crtc.H_DISP = 8'd80;   // 80 // 40
    defparam crtc.H_SYNCPOS = 8'd90;    // 90 // 45
    defparam crtc.H_SYNCWIDTH = 4'd10;
    defparam crtc.V_TOTAL = 7'd31;
    defparam crtc.V_TOTALADJ = 5'd6;
    defparam crtc.V_DISP = 7'd25;
    defparam crtc.V_SYNCPOS = 7'd28;
    defparam crtc.V_MAXSCAN = 5'd7;
    defparam crtc.C_START = 7'd6;
    defparam crtc.C_END = 5'd7;
     

    // In graphics mode, memory address MSB comes from CRTC row
    // which produces the weird CGA "interlaced" memory map
    assign pcjr_graphics = pcjr_video & grph_mode;
    assign pcjr_addr_use = (pcjr_addr_mode != 2'b00);
    assign pcjr_addr_hi = (pcjr_addr_mode == 2'b11);
    assign pixel_addr13 = pcjr_graphics ? (pcjr_addr_use ? row_addr[0] : 1'b0) :
                         (grph_mode ? row_addr[0] : crtc_addr[12]);

    // Address bit 14 is only used for Tandy/PCjr modes (32K RAM)
    assign pixel_addr14 = pcjr_graphics ? (pcjr_addr_hi ? row_addr[1] : 1'b0) :
                         (grph_mode ? row_addr[1] : 1'b0);

    wire tandy_16_gfx = tandy_16_mode & grph_mode & hres_mode;

    // Sequencer state machine
    cga_sequencer sequencer (
        .clk(clk),
        .clk_seq(clkdiv),
        .vram_read(vram_read),
        .vram_read_a0(vram_read_a0),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .hres_mode(hres_mode),
        .crtc_clk(crtc_clk),
        .charrom_read(charrom_read),
        .disp_pipeline(disp_pipeline),
        .isa_op_enable(isa_op_enable),
        .hclk(hclk),
        .lclk(lclk),
        .tandy_16_gfx(tandy_16_gfx),
		  .tandy_color_16(tandy_color_16)
    );

    // Pixel pusher
    cga_pixel pixel (
        .clk(clk),
        .clk_seq(clkdiv),
        .hres_mode(hres_mode),
        .grph_mode(grph_mode),
        .bw_mode(bw_mode),
        .mode_640(mode_640),
        .tandy_16_mode(tandy_16_mode),
        .thin_font(thin_font),
        .vram_data(ram_1_d),
        .vram_read_char(vram_read_char),
        .vram_read_att(vram_read_att),
        .disp_pipeline(disp_pipeline),
        .charrom_read(charrom_read),
        .display_enable(display_enable),
        .cursor(cursor),
        .row_addr(row_addr),
        .blink_enabled(blink_enabled),
        .blink(blink),
        .hsync(hsync_int),
        .vsync(vsync_l),
        .video_enabled(video_enabled),
        .cga_color_reg(cga_color_reg),
        .palette_write(palette_write),
        .palette_index(palette_index),
        .palette_value(palette_value),
        .tandy_bordercol(border_color),
        .tandy_color_4(tandy_color_4),
        .tandy_color_16(tandy_color_16),
        .pcjr_video(pcjr_video),
        .pcjr_palette_mask(pcjr_palette_mask),
        .video(video)
    );

    // Generate blink signal for cursor and character
    always @ (posedge clk)
    begin
        if (~splashscreen) begin
        if (blink_counter == BLINK_MAX) begin
            blink_counter <= 0;
            blink <= ~blink;
        end else begin
            blink_counter <= blink_counter + 1'b1;
        end
        end
    end

    /*
    cga_scandoubler scandoubler (
        .clk(clk),
        .line_reset(line_reset),
        .video(video),          
        .dbl_hsync(dbl_hsync),
        .dbl_video(dbl_video)
    );
    */

endmodule
