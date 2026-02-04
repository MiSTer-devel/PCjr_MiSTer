//
// MiSTer PCXT RAM
// Ported by @spark2k06
//
// Based on KFPC-XT written by @kitune-san
//
module RAM (
    input   logic           clock,
    input   logic           reset,
    input   logic           enable_sdram,
    output  logic           initilized_sdram,
    // I/O Ports
    input   logic   [19:0]  address,
    input   logic   [7:0]   internal_data_bus,
    output  logic   [7:0]   data_bus_out,
    input   logic           memory_read_n,
    input   logic           memory_write_n,
    input   logic           no_command_state,
    output  logic           memory_access_ready,
    output  logic           ram_address_select_n,
    // SDRAM
    output  logic   [12:0]  sdram_address,
    output  logic           sdram_cke,
    output  logic           sdram_cs,
    output  logic           sdram_ras,
    output  logic           sdram_cas,
    output  logic           sdram_we,
    output  logic   [1:0]   sdram_ba,
    input   logic   [15:0]  sdram_dq_in,
    output  logic   [15:0]  sdram_dq_out,
    output  logic           sdram_dq_io,
    output  logic           sdram_ldqm,
    output  logic           sdram_udqm,
     // EMS
     input   logic   [6:0]   map_ems[0:3],
     input   logic           ems_b1,
     input   logic           ems_b2,
     input   logic           ems_b3,
     input   logic           ems_b4,
     // BIOS
     input  logic    [1:0]  bios_protect_flag,
     input  logic           tandy_bios_flag,
    // Optional flags
    input  logic           enable_a000h,
    // Wait mode
    input   logic           wait_count_clk_en,
    input   logic   [1:0]   ram_read_wait_cycle,
    input   logic   [1:0]   ram_write_wait_cycle,
    // RAM size selection
    input   logic   [3:0]   ram_size,  // 0=640KB, 1=576KB, 2=512KB, 3=448KB, 4=384KB, 5=320KB, 6=256KB, 7=192KB, 8=128KB
    // Cold boot signal (forces BIOS memory test by clearing reset_flag at 0x472)
    input   logic           cold_boot
);

    typedef enum {IDLE, RAM_WRITE_1, RAM_WRITE_2, RAM_READ_1, RAM_READ_2, COMPLETE_RAM_RW, WAIT} state_t;

    state_t         state;
    state_t         next_state;
    logic   [21:0]  latch_address;
    logic   [7:0]   latch_data;
    logic           write_command;
    logic           read_command;
    logic           prev_no_command_state;
    logic           enable_refresh;
    logic           write_protect;
    logic           tandy_bios_select;

    logic   [1:0]   read_wait_count;
    logic   [1:0]   write_wait_count;
    logic           access_ready;

    //
    // Cold boot logic: force reset_flag at 0x472-0x473 to return 0
    // until it has been written, causing BIOS to perform memory test
    //
    logic           reset_flag_written;
    logic           cold_boot_ff1;
    logic           cold_boot_ff2;
    wire            cold_boot_pulse = cold_boot_ff1 & ~cold_boot_ff2;
    wire            is_reset_flag_addr = (address == 20'h00472) | (address == 20'h00473);

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cold_boot_ff1 <= 1'b0;
            cold_boot_ff2 <= 1'b0;
        end else begin
            cold_boot_ff1 <= cold_boot;
            cold_boot_ff2 <= cold_boot_ff1;
        end
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            reset_flag_written <= 1'b0;
        else if (cold_boot_pulse)
            reset_flag_written <= 1'b0;  // Clear on cold boot
        else if (is_reset_flag_addr && ~memory_write_n && ~ram_address_select_n)
            reset_flag_written <= 1'b1;  // Set when reset_flag address is written
    end

    //
    // Memory size limit logic
    // Conventional RAM ranges based on ram_size setting:
    // ram_size=0: 640KB (00000-9FFFF)
    // ram_size=1: 576KB (00000-8FFFF)
    // ram_size=2: 512KB (00000-7FFFF)
    // ram_size=3: 448KB (00000-6FFFF)
    // ram_size=4: 384KB (00000-5FFFF)
    // ram_size=5: 320KB (00000-4FFFF)
    // ram_size=6: 256KB (00000-3FFFF)
    // ram_size=7: 192KB (00000-2FFFF)
    // ram_size=8: 128KB (00000-1FFFF)
    //
    logic ram_within_limit;
    logic is_upper_memory;

    assign is_upper_memory = (address[19:18] == 2'b11);  // C0000-FFFFF (ROM/BIOS area)

    always_comb begin
        case (ram_size)
            4'd0:    ram_within_limit = (address[19:16] <= 4'h9);  // 640KB
            4'd1:    ram_within_limit = (address[19:16] <= 4'h8);  // 576KB
            4'd2:    ram_within_limit = (address[19:16] <= 4'h7);  // 512KB
            4'd3:    ram_within_limit = (address[19:16] <= 4'h6);  // 448KB
            4'd4:    ram_within_limit = (address[19:16] <= 4'h5);  // 384KB
            4'd5:    ram_within_limit = (address[19:16] <= 4'h4);  // 320KB
            4'd6:    ram_within_limit = (address[19:16] <= 4'h3);  // 256KB
            4'd7:    ram_within_limit = (address[19:16] <= 4'h2);  // 192KB
            4'd8:    ram_within_limit = (address[19:16] <= 4'h1);  // 128KB
            default: ram_within_limit = (address[19:16] <= 4'h9);  // Default 640KB
        endcase
    end

    //
    // RAM Address Select (0x00000-0xAFFFF and 0xC0000-0xFFFFF)
    //
    assign ram_address_select_n = ~(enable_sdram && ~(address[19:16] == 4'b1011) &&  // B0000h reserved for VRAM
	                               ~(address[19:16] == 4'b1010));                     // A0000h is disabled
	 

    assign tandy_bios_select    = tandy_bios_flag & (address[19:16] == 4'b1111);


    //
    // Write protect
    //
    wire upper_cart_area = (address[19:16] >= 4'hC) && (address[19:16] <= 4'hE);
    assign write_protect = (bios_protect_flag[1] & (address[19:16] == 4'hF)) |
                           (bios_protect_flag[0] & upper_cart_area);


    //
    // I/O Ports
    //
    // Address
    always_comb begin
        latch_address   = {1'b0, tandy_bios_select, address};
    end

    // Data
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            latch_data      <= 0;
        else
            latch_data      <= internal_data_bus;
    end

    // Write Command
    assign write_command = ~ram_address_select_n & ~memory_write_n & ~write_protect;

    // Read Command
    assign read_command  = ~ram_address_select_n & ~memory_read_n;

    // Generate refresh timing
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            prev_no_command_state   <= 1'b0;
        end
        else begin
            prev_no_command_state   <= no_command_state;
        end
    end

    assign  enable_refresh  = no_command_state & ~prev_no_command_state;


    //
    // SDRAM Controller
    //
    logic   [24:0]  access_address;
    logic   [9:0]   access_num;
    logic   [15:0]  access_data_in;
    logic   [15:0]  access_data_out;
    logic           write_request;
    logic           read_request;
    logic           write_flag;
    logic           read_flag;
    logic           idle;
    logic           refresh_mode;

    KFSDRAM u_KFSDRAM (
        .sdram_clock        (clock),
        .sdram_reset        (reset),
        .address            (access_address),
        .access_num         (access_num),
        .data_in            (access_data_in),
        .data_out           (access_data_out),
        .write_request      (write_request),
        .read_request       (read_request),
        .enable_refresh     (enable_refresh),
        .write_flag         (write_flag),
        .read_flag          (read_flag),
        .idle               (idle),
        .refresh_mode       (refresh_mode),
        .sdram_address      (sdram_address),
        .sdram_cke          (sdram_cke),
        .sdram_cs           (sdram_cs),
        .sdram_ras          (sdram_ras),
        .sdram_cas          (sdram_cas),
        .sdram_we           (sdram_we),
        .sdram_ba           (sdram_ba),
        .sdram_dq_in        (sdram_dq_in),
        .sdram_dq_out       (sdram_dq_out),
        .sdram_dq_io        (sdram_dq_io)
    );


    //
    // State machine
    //
    always_comb begin
        next_state = state;
        casez (state)
            IDLE: begin
                if (write_command)
                    next_state = RAM_WRITE_1;
                else if (read_command)
                    next_state = RAM_READ_1;
            end
            RAM_WRITE_1: begin
                if (~write_command)
                    next_state = WAIT;
                if (write_flag)
                    next_state = RAM_WRITE_2;
            end
            RAM_WRITE_2: begin
                if (~write_command)
                    next_state = WAIT;
                if (~write_flag)
                    next_state = COMPLETE_RAM_RW;
            end
            RAM_READ_1: begin
                if (~read_command)
                    next_state = WAIT;
                if (read_flag)
                    next_state = RAM_READ_2;
            end
            RAM_READ_2: begin
                if (~read_command)
                    next_state = WAIT;
                if (~read_flag)
                    next_state = COMPLETE_RAM_RW;
            end
            COMPLETE_RAM_RW: begin
                if ((~write_command) && (~read_command))
                    next_state = IDLE;
            end
            WAIT: begin
                if (idle)
                    next_state = IDLE;
            end
        endcase
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            state = IDLE;
        else
            state = next_state;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            initilized_sdram <= 1'b0;
        else if (idle)
            initilized_sdram <= 1'b1;
        else
            initilized_sdram <= initilized_sdram;
    end


    //
    // Output SDRAM Control Signals
    //
    always_comb begin
        casez (state)
            IDLE: begin
                access_address  = {7'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = write_command ? 1'b1 : 1'b0;
                read_request    = read_command  ? 1'b1 : 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_1: begin
                access_address  = {7'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = 1'b1;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_WRITE_2: begin
                access_address  = {7'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = {8'h00, latch_data};
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_1: begin
                access_address  = {7'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b1;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            RAM_READ_2: begin
                access_address  = {7'h00, latch_address};
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            COMPLETE_RAM_RW: begin
                access_address  = 25'h0000000;
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b0;
                sdram_udqm      = 1'b0;
            end
            WAIT: begin
                access_address  = 25'h0000000;
                access_num      = 10'h001;
                access_data_in  = 16'h0000;
                write_request   = 1'b0;
                read_request    = 1'b0;
                sdram_ldqm      = 1'b1;
                sdram_udqm      = 1'b1;
            end
        endcase
    end


    //
    // Databus Out
    //
    logic   [7:0]   data_bus_out_reg;

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            data_bus_out_reg    <= 0;
        else if (read_flag)
            data_bus_out_reg    <= access_data_out[7:0];
        else
            data_bus_out_reg    <= data_bus_out_reg;
    end

    // Force reset_flag at 0x472-0x473 to return 0 after cold boot until written
    // This ensures BIOS performs memory test on OSD reset
    wire cold_boot_override = is_reset_flag_addr && ~reset_flag_written;
    assign  data_bus_out = ~read_command ? 0 : cold_boot_override ? 8'h00 : ~read_flag ? data_bus_out_reg : access_data_out[7:0];


    //
    // Ready/Wait Signal
    //
    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            access_ready <= 1'b0;
        else if (state == COMPLETE_RAM_RW)
            access_ready <= 1'b1;
        else if (state == IDLE)
            access_ready <= idle;
        else if ((write_command) && (refresh_mode))
            access_ready <= 1'b0;
        else if ((read_command)  && (refresh_mode))
            access_ready <= 1'b0;
        else
            access_ready <= access_ready;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            read_wait_count     <= 0;
        else if (~read_command)
            read_wait_count     <= ram_read_wait_cycle;
        else if ((wait_count_clk_en) && (read_wait_count != 0))
            read_wait_count     <= read_wait_count - 1;
        else
            read_wait_count     <= read_wait_count;
    end

    always_ff @(posedge clock, posedge reset) begin
        if (reset)
            write_wait_count    <= 0;
        else if (~write_command)
            write_wait_count    <= ram_write_wait_cycle;
        else if ((wait_count_clk_en) && (write_wait_count != 0))
            write_wait_count    <= write_wait_count - 1;
        else
            write_wait_count    <= write_wait_count;
    end

    assign  memory_access_ready = ((~ram_address_select_n) && ((~memory_read_n) || (~memory_write_n)))
                                        ? (access_ready & ((read_wait_count==0) || (~read_command)) & ((write_wait_count==0) || (~write_command))) : 1'b1;

endmodule
