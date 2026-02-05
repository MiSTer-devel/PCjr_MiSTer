//
// MiSTer PCXT Peripherals
// Ported by @spark2k06
//
// Based on KFPC-XT written by @kitune-san
//
module PERIPHERALS #(
        parameter ps2_over_time = 16'd1000,
		parameter clk_rate = 28'd50000000
    ) (
        input   logic           clock,
        input   logic           clk_sys,
        input   logic           cpu_clock,
        input   logic           peripheral_clock,
        input   logic   [1:0]   clk_select,
        input   logic           reset,
        // CPU
        output  logic           interrupt_to_cpu,
        output  logic           nmi_to_cpu,
        // Bus Arbiter
        input   logic           interrupt_acknowledge_n,
        output  logic           dma_chip_select_n,
        output  logic           dma_page_chip_select_n,
        // SplashScreen
        input   logic           splashscreen,
        input   logic           status0_clear,
        // VGA
        output  logic           std_hsyncwidth,
        input   logic           composite,
        input   logic           video_output,
        input   logic           clk_vga_cga,
        input   logic           enable_cga,
        output  logic           de_o,
        output  logic   [5:0]   VGA_R,
        output  logic   [5:0]   VGA_G,
        output  logic   [5:0]   VGA_B,
        output  logic           VGA_HSYNC,
        output  logic           VGA_VSYNC,
        output  logic           VGA_HBlank,
        output  logic           VGA_VBlank,
        output  logic           VGA_VBlank_border,
        // I/O Ports
        input   logic   [19:0]  address,
        output  logic   [19:0]  latch_address,
        input   logic   [7:0]   internal_data_bus,
        output  logic   [7:0]   data_bus_out,
        output  logic           data_bus_out_from_chipset,
        input   logic   [7:0]   interrupt_request,
        input   logic           io_read_n,
        input   logic           io_write_n,
        input   logic           memory_read_n,
        input   logic           memory_write_n,
        input   logic           address_enable_n,
        // Peripherals
        output  logic   [2:0]   timer_counter_out,
        output  logic           speaker_out,
        output  logic   [7:0]   port_a_out,
        output  logic           port_a_io,
        input   logic   [7:0]   port_b_in,
        output  logic   [7:0]   port_b_out,
        output  logic           port_b_io,
        input   logic   [7:0]   port_c_in,
        output  logic   [7:0]   port_c_out,
        output  logic   [7:0]   port_c_io,
        input   logic           ps2_clock,
        input   logic           ps2_data,
        output  logic           ps2_clock_out,
        output  logic           ps2_data_out,
        input   logic           ps2_mouseclk_in,
        input   logic           ps2_mousedat_in,
        output  logic           ps2_mouseclk_out,
        output  logic           ps2_mousedat_out,
        input   logic   [4:0]   joy_opts,
        input   logic   [13:0]  joy0,
        input   logic   [13:0]  joy1,
        input   logic   [15:0]  joya0,
        input   logic   [15:0]  joya1,
        // JTOPL
        output  logic   [15:0]  jtopl2_snd_e,
        input   logic   [1:0]   opl2_io,
        // C/MS Audio
        input   logic           cms_en,
        output  reg     [15:0]  o_cms_l,
        output  reg     [15:0]  o_cms_r,
        // TANDY
        input   logic           tandy_video,
        output  logic   [10:0]  tandy_snd_e,
        output  logic           tandy_snd_rdy,
        output  logic           tandy_16_gfx,
        output  logic           tandy_color_16,
        // UART
        input   logic           clk_uart,
        input   logic           uart2_rx,
        output  logic           uart2_tx,
        input   logic           uart2_cts_n,
        input   logic           uart2_dcd_n,
        input   logic           uart2_dsr_n,
        output  logic           uart2_rts_n,
        output  logic           uart2_dtr_n,
        // EMS
        input   logic           ems_enabled,
        input   logic   [1:0]   ems_address,
        output  reg     [6:0]   map_ems[0:3], // Segment hx000, hx400, hx800, hxC00
        output  reg             ena_ems[0:3], // Enable Segment Map hx000, hx400, hx800, hxC00
        output  logic           ems_b1,
        output  logic           ems_b2,
        output  logic           ems_b3,
        output  logic           ems_b4,
        // FDD
        input   logic   [15:0]  mgmt_address,
        input   logic           mgmt_read,
        output  logic   [15:0]  mgmt_readdata,
        input   logic           mgmt_write,
        input   logic   [15:0]  mgmt_writedata,
        input   logic   [1:0]   floppy_wp,
        output  logic   [1:0]   fdd_present,
        output  logic   [1:0]   fdd_request,
        output  logic           fdd_dma_req,
        input   logic           fdd_dma_ack,
        input   logic           terminal_count,
        // XTCTL DATA
        output  logic   [7:0]   xtctl = 8'h00,
        // Others
        output  logic           pause_core,
        input   logic           cga_hw,
        input   logic           hercules_hw,
        output  logic           swap_video,
        input   logic   [3:0]   crt_h_offset,
        input   logic   [2:0]   crt_v_offset
        
    );

    wire [4:0] clkdiv;
    wire grph_mode;
    wire hres_mode;

    wire tandy_video_en = tandy_video;
    assign tandy_16_gfx = tandy_video_en & grph_mode & hres_mode;

    always_comb begin
        map_ems = '{default:7'h00};
        ena_ems = '{default:1'b0};
    end

    assign ems_b1 = 1'b0;
    assign ems_b2 = 1'b0;
    assign ems_b3 = 1'b0;
    assign ems_b4 = 1'b0;


    //
    // CPU clock edge
    //
    logic   prev_cpu_clock;

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            prev_cpu_clock <= 1'b0;
        else
            prev_cpu_clock <= cpu_clock;
    end

    wire    cpu_clock_posedge = ~prev_cpu_clock & cpu_clock;
    wire    cpu_clock_negedge = prev_cpu_clock & ~cpu_clock;


    //
    // chip select
    //
    logic   [7:0]   chip_select_n;

    always_comb
    begin
        if (iorq & ~address_enable_n & ~address[9] & ~address[8] & ~address[4])
        begin
            casez (address[7:5])
                3'b000:
                    chip_select_n = 8'b11111110;
                3'b001:
                    chip_select_n = 8'b11111101;
                3'b010:
                    chip_select_n = 8'b11111011;
                3'b011:
                    chip_select_n = 8'b11110111;
                3'b100:
                    chip_select_n = 8'b11101111;
                3'b101:
                    chip_select_n = 8'b11011111;
                3'b110:
                    chip_select_n = 8'b10111111;
                3'b111:
                    chip_select_n = 8'b01111111;
                default:
                    chip_select_n = 8'b11111111;
            endcase
        end
        else
        begin
            chip_select_n = 8'b11111111;
        end
    end

    wire    iorq = ~io_read_n | ~io_write_n;

    assign  dma_chip_select_n       = chip_select_n[0]; // 0x00 .. 0x1F
    wire    interrupt_chip_select_n = chip_select_n[1]; // 0x20 .. 0x3F
    wire    timer_chip_select_n     = chip_select_n[2]; // 0x40 .. 0x5F
    wire    ppi_chip_select_n       = chip_select_n[3]; // 0x60 .. 0x7F
    assign  dma_page_chip_select_n  = chip_select_n[4]; // 0x80 .. 0x8F
    wire    nmi_chip_select_n       = chip_select_n[5]; // 0xA0 .. 0xBF
    wire    joystick_select         = (iorq && ~address_enable_n && address[15:3] == (16'h0200 >> 3)); // 0x200 .. 0x207
    wire    tandy_chip_select_n     = chip_select_n[6]; // 0xC0 .. 0xDF
    wire    nmi_mask_register       = (tandy_video_en && ~nmi_chip_select_n);
    logic   prev_nmi_mask_write_n;
    wire    nmi_mask_write_n        = ~nmi_mask_register | io_write_n;
    wire    write_nmi_mask          = ~prev_nmi_mask_write_n & nmi_mask_write_n;
    logic   pcjr_nmi_enable;
    logic   ir_test_enable;

    wire    cga_mem_select          = ~iorq && ~address_enable_n && enable_cga & (address[19:15] == 5'b10111); // B8000 - BFFFF (16 KB / 32 KB)
    // FIX: uart_chip_select must NOT include iorq because iorq_uart detects the rising edge
    // of io_write_n (when io_write_n=1), but iorq requires io_write_n=0. They can never be true simultaneously.
    // The address is stable during the entire bus cycle, so we only need to check the address.
    // PCjr uses 0x2F8 for internal COM port (unlike standard PC which uses 0x3F8)
    wire    uart_chip_select        = ({address[15:3], 3'd0} == 16'h02F8);  // PCjr internal COM at 0x2F8
    // uart2 is for external serial (directly exposed to user I/O pins)
    wire    uart2_chip_select       = ({address[15:3], 3'd0} == 16'h03F8);  // External at 0x3F8
    wire    lpt_chip_select         = (iorq && ~address_enable_n && address[15:1] == (16'h0378 >> 1)); // 0x378 ... 0x379
	 wire    lpt_ctrl_select         = (iorq && ~address_enable_n && address[15:0] == 16'h037A); // 0x37A
    wire    tandy_page_chip_select  = tandy_video_en && iorq && ~address_enable_n && address[15:0] == 16'h03DF;
    wire    pcjr_memctrl_32k        = (tandy_page_data[7:6] == 2'b11);
    wire    [1:0] pcjr_addr_mode    = tandy_page_data[7:6];
    wire    [2:0] pcjr_b8000_page   = pcjr_memctrl_32k ? {1'b0, tandy_page_data[5:4]} : tandy_page_data[5:3];
    wire    [2:0] pcjr_vram_page    = pcjr_memctrl_32k ? {1'b0, tandy_page_data[2:1]} : tandy_page_data[2:0];
    wire    [2:0] pcjr_phys_page    = pcjr_memctrl_32k ? {1'b0, address[16:15]} : address[16:14];
    wire    video_mem_select        = tandy_video_en && ~iorq && ~address_enable_n &&
                                      (address[19:17] == 3'b000) &&
                                      (pcjr_memctrl_32k ? ((pcjr_phys_page[1:0] == pcjr_vram_page[1:0]) ||
                                                           (pcjr_phys_page[1:0] == pcjr_b8000_page[1:0])) :
                                                          ((pcjr_phys_page == pcjr_vram_page) ||
                                                           (pcjr_phys_page == pcjr_b8000_page)));
    wire    xtctl_chip_select       = (iorq && ~address_enable_n && address[15:0] == 16'h8888);
    wire    rtc_chip_select         = (iorq && ~address_enable_n && address[15:1] == (16'h02C0 >> 1)); // 0x2C0 .. 0x2C1
    wire    floppy0_chip_select_n   = ~(~address_enable_n && ({address[15:3], 3'd0} == 16'h00F0));

    //
    // I/O Ports
    //
    // Address
    always_comb begin
        latch_address = address;
    end


    //
    // 8259
    //
    logic           timer_interrupt;
    logic           keybord_interrupt;
    logic           uart_interrupt;
    logic           fdd_interrupt;
    logic           uart2_interrupt;
    logic   [7:0]   interrupt_data_bus_out;
    logic           interrupt_to_cpu_buf;

    KF8259 u_KF8259 
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (interrupt_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (address[0]),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (interrupt_data_bus_out),

        // I/O
        .cascade_in                 (3'b000),
        //.cascade_out                (),
        //.cascade_io                 (),
        .slave_program_n            (1'b1),
        //.buffer_enable              (),
        //.slave_program_or_enable_buffer     (),
        .interrupt_acknowledge_n    (interrupt_acknowledge_n),
        .interrupt_to_cpu           (interrupt_to_cpu_buf),
        .interrupt_request          ({interrupt_request[7],
                                        fdd_interrupt,
                                        (interrupt_request[5] | video_irq),
                                        uart2_interrupt,   // IRQ4 - external UART at 0x3F8
                                        uart_interrupt,    // IRQ3 - internal PCjr UART at 0x2F8
                                        interrupt_request[2],
                                        keybord_interrupt,
                                        timer_interrupt})
    );

    always_ff @(posedge clock, posedge reset)
        if (reset)
            interrupt_to_cpu    <= 1'b0;
        else if (cpu_clock_negedge)
            interrupt_to_cpu    <= interrupt_to_cpu_buf;
        else
            interrupt_to_cpu    <= interrupt_to_cpu;


    //
    // 8253
    //
    logic   prev_p_clock_1;
    logic   prev_p_clock_2;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            prev_p_clock_1 <= 1'b0;
            prev_p_clock_2 <= 1'b0;
        end
        else
        begin
            prev_p_clock_1 <= peripheral_clock;
            prev_p_clock_2 <= prev_p_clock_1;

        end
    end

    wire    p_clock_posedge = prev_p_clock_1 & ~prev_p_clock_2;

    logic   timer_clock;
    logic   timer_1_clock;
    wire    channel_1_clock_select = nmi_mask_register_data[5];
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            timer_clock         <= 1'b0;
        else if (p_clock_posedge)
            timer_clock         <= ~timer_clock;
        else
            timer_clock         <= timer_clock;
    end

    assign timer_1_clock = channel_1_clock_select ? timer_counter_out[0] : timer_clock;

    logic   [7:0]   timer_data_bus_out;

    wire    tim2gatespk = port_b_out[0] & ~port_b_io;
    wire    spkdata     = port_b_out[1] & ~port_b_io;

    KF8253 u_KF8253 
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (timer_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (address[1:0]),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (timer_data_bus_out),

        // I/O
        .counter_0_clock            (timer_clock),
        .counter_0_gate             (1'b1),
        .counter_0_out              (timer_counter_out[0]),
        .counter_1_clock            (timer_1_clock),
        .counter_1_gate             (1'b1),
        .counter_1_out              (timer_counter_out[1]),
        .counter_2_clock            (timer_clock),
        .counter_2_gate             (tim2gatespk),
        .counter_2_out              (timer_counter_out[2])
    );

    assign  timer_interrupt = timer_counter_out[0];
    assign  speaker_out     = timer_counter_out[2] & spkdata;

    //
    // 8255
    //
    logic   [7:0]   ppi_data_bus_out;
    logic   [7:0]   port_a_in;
    logic           prev_keybord_irq;
    logic           prev_pcjr_keybd_in;
    logic           keybd_latch;
    logic           pcjr_kbd_data;
    wire            pcjr_keybd_in = ~pcjr_kbd_data;
    wire            pcjr_cable_connected_n = 1'b0;
    wire    [7:0]   pcjr_port_c_in = {
        pcjr_cable_connected_n,
        pcjr_keybd_in,
        timer_counter_out[2],
        timer_counter_out[2],
        port_c_in[3:1],
        keybd_latch
    };
    wire    [7:0]   port_c_in_mux = pcjr_port_c_in;

    KF8255 u_KF8255 
    (
        // Bus
        .clock                      (clock),
        .reset                      (reset),
        .chip_select_n              (ppi_chip_select_n),
        .read_enable_n              (io_read_n),
        .write_enable_n             (io_write_n),
        .address                    (address[1:0]),
        .data_bus_in                (internal_data_bus),
        .data_bus_out               (ppi_data_bus_out),

        // I/O
        .port_a_in                  (port_a_in),
        .port_a_out                 (port_a_out),
        .port_a_io                  (port_a_io),
        .port_b_in                  (8'hFF),
        .port_b_out                 (port_b_out),
        .port_b_io                  (port_b_io),
        .port_c_in                  (port_c_in_mux),
        .port_c_out                 (port_c_out),
        .port_c_io                  (port_c_io)
    );

    //
    // KFPS2KB
    //
    logic           ps2_send_clock;
    logic           keybord_irq;
    logic           uart_irq;
    logic           uart2_irq;
    logic   [7:0]   keycode_buf;
    logic   [7:0]   keycode;
    logic           prev_ps2_reset;
    logic           prev_ps2_reset_n;
    logic           lock_recv_clock;
    logic           swap_video_buffer_1;
    logic           swap_video_buffer_2;

    logic   pcjr_clear_keycode;
    wire    clear_keycode = pcjr_clear_keycode;
    wire    ps2_reset_n   = ~tandy_video ? port_b_out[6] : 1'b1;

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            prev_ps2_reset_n <= 1'b0;
        else
            prev_ps2_reset_n <= ps2_reset_n;
    end

    KFPS2KB u_KFPS2KB 
    (
        // Bus
        .clock                      (clock),
        .peripheral_clock           (peripheral_clock),
        .reset                      (reset),

        // PS/2 I/O
        .device_clock               (ps2_clock | lock_recv_clock),
        .device_data                (ps2_data),

        // I/O
        .irq                        (keybord_irq),
        .keycode                    (keycode_buf),
        .clear_keycode              (clear_keycode),
        .pause_core                 (pause_core),
        .swap_video                 (swap_video_buffer_1),
        .video_output               (video_output),
        .tandy_video                (tandy_video_en)
    );

    assign  keycode = ps2_reset_n ? keycode_buf : 8'h80;

    // PCjr IR keyboard encoder
    // Protocol: Manchester encoding with 42 half-bits per frame
    // Format: Start(2) + Data(16) + Parity(2) + Stop(22) = 42 half-bits
    // Each data/parity bit transmitted as [value, ~value]
    // Timing: ~220us per half-bit = 11000 cycles at 50MHz
    localparam [15:0] PCJR_HALF_BIT_CYCLE = 16'd11000 - 16'd1;

    // Keycode queue (16 entries, matching PCem) to avoid losing keys during transmission
    logic   [7:0]   pcjr_key_queue[0:15];
    logic   [3:0]   pcjr_queue_head;    // Read pointer
    logic   [3:0]   pcjr_queue_tail;    // Write pointer
    wire            pcjr_queue_empty = (pcjr_queue_head == pcjr_queue_tail);
    wire    [7:0]   pcjr_queue_front = pcjr_key_queue[pcjr_queue_head];

    logic   [7:0]   pcjr_scancode;      // Scancode being transmitted
    logic   [5:0]   pcjr_half_bit_pos;  // Position in 42 half-bit frame (0-41)
    logic   [15:0]  pcjr_phase_count;   // Cycle counter for timing
    logic           pcjr_sending;       // Transmission in progress
    logic           pcjr_parity;        // Odd parity bit
    logic           pcjr_current_bit;   // Current half-bit value to transmit

    // Flag to track if we've already processed the current IRQ
    logic pcjr_irq_processed;

    // Typematic rate limiter - limits auto-repeat to ~10 chars/second like real PCjr keyboard
    // At 50MHz: 100ms = 5,000,000 cycles, use 23-bit counter
    localparam [22:0] PCJR_TYPEMATIC_PERIOD = 23'd5000000 - 23'd1;  // ~100ms between repeats
    logic [22:0] pcjr_typematic_timer;
    logic [6:0]  pcjr_last_make_key;     // Last make code (without bit 7) for typematic
    wire         pcjr_typematic_active = |pcjr_typematic_timer;  // Timer still running

    // Check if incoming keycode should be filtered:
    // - It's a make code (bit 7 clear)
    // - Same key as last make code
    // - Typematic timer is still running
    wire pcjr_is_repeat_filtered = !keycode_buf[7] &&
                                   (keycode_buf[6:0] == pcjr_last_make_key) &&
                                   pcjr_typematic_active;

    // IRQ handling and queue management
    // Note: E0/E1 prefixes are now handled inside KFPS2KB and don't generate IRQ
    // Typematic throttling: limit auto-repeat rate to ~10 chars/second
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset) begin
            pcjr_clear_keycode <= 1'b0;
            pcjr_irq_processed <= 1'b0;
            pcjr_queue_tail <= 4'd0;
            pcjr_typematic_timer <= 23'd0;
            pcjr_last_make_key <= 7'd0;
            pcjr_key_queue[0]  <= 8'h00;
            pcjr_key_queue[1]  <= 8'h00;
            pcjr_key_queue[2]  <= 8'h00;
            pcjr_key_queue[3]  <= 8'h00;
            pcjr_key_queue[4]  <= 8'h00;
            pcjr_key_queue[5]  <= 8'h00;
            pcjr_key_queue[6]  <= 8'h00;
            pcjr_key_queue[7]  <= 8'h00;
            pcjr_key_queue[8]  <= 8'h00;
            pcjr_key_queue[9]  <= 8'h00;
            pcjr_key_queue[10] <= 8'h00;
            pcjr_key_queue[11] <= 8'h00;
            pcjr_key_queue[12] <= 8'h00;
            pcjr_key_queue[13] <= 8'h00;
            pcjr_key_queue[14] <= 8'h00;
            pcjr_key_queue[15] <= 8'h00;
        end
        else begin
            // Decrement typematic timer
            if (pcjr_typematic_active)
                pcjr_typematic_timer <= pcjr_typematic_timer - 23'd1;

            if (keybord_irq && !pcjr_irq_processed) begin
                // New keycode arrived - process it once
                pcjr_clear_keycode <= 1'b1;
                pcjr_irq_processed <= 1'b1;

                // Enqueue logic with typematic filtering:
                // - Break codes (bit 7 set): ALWAYS enqueue, reset timer
                // - Make codes: only enqueue if not filtered by typematic timer
                if (keycode_buf[7]) begin
                    // Break code - always enqueue, clear typematic state
                    pcjr_key_queue[pcjr_queue_tail] <= keycode_buf;
                    pcjr_queue_tail <= pcjr_queue_tail + 4'd1;
                    pcjr_typematic_timer <= 23'd0;  // Allow immediate re-press
                end
                else if (!pcjr_is_repeat_filtered) begin
                    // Make code - enqueue and start typematic timer
                    pcjr_key_queue[pcjr_queue_tail] <= keycode_buf;
                    pcjr_queue_tail <= pcjr_queue_tail + 4'd1;
                    pcjr_last_make_key <= keycode_buf[6:0];
                    pcjr_typematic_timer <= PCJR_TYPEMATIC_PERIOD;
                end
                // else: filtered repeat - don't enqueue, don't reset timer
            end
            else if (!keybord_irq) begin
                // IRQ cleared - ready for next keycode
                pcjr_clear_keycode <= 1'b0;
                pcjr_irq_processed <= 1'b0;
            end
            else begin
                // IRQ still high but already processed
                pcjr_clear_keycode <= 1'b0;
            end
        end
    end

    // State machine for frame transmission
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset) begin
            pcjr_scancode       <= 8'h00;
            pcjr_half_bit_pos   <= 6'd0;
            pcjr_sending        <= 1'b0;
            pcjr_parity         <= 1'b0;
            pcjr_queue_head     <= 4'd0;
        end
        else if (~pcjr_sending) begin
            // Idle - check queue for pending keycodes
            // IMPORTANT: Only start transmission when:
            //   1. Queue not empty
            //   2. Previous key was acknowledged (keybd_latch cleared by reading port 0xA0)
            // This matches PCem behavior which waits for !latched before sending next key
            if (!pcjr_queue_empty && !keybd_latch) begin
                // Dequeue and start transmission
                pcjr_scancode       <= pcjr_queue_front;
                pcjr_half_bit_pos   <= 6'd0;
                pcjr_sending        <= 1'b1;
                pcjr_parity         <= ^pcjr_queue_front;  // Calculate parity
                pcjr_queue_head     <= pcjr_queue_head + 4'd1;
            end
        end
        else begin
            // Sending - advance half-bit position on timer expiry
            if (~|pcjr_phase_count) begin
                if (pcjr_half_bit_pos == 6'd41) begin
                    // Frame complete
                    pcjr_sending      <= 1'b0;
                    pcjr_half_bit_pos <= 6'd0;
                end
                else begin
                    pcjr_half_bit_pos <= pcjr_half_bit_pos + 6'd1;
                end
            end
        end
    end

    // Timer for half-bit timing (~220us)
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            pcjr_phase_count <= PCJR_HALF_BIT_CYCLE;
        else if (~pcjr_sending)
            pcjr_phase_count <= PCJR_HALF_BIT_CYCLE;
        else if (~|pcjr_phase_count)
            pcjr_phase_count <= PCJR_HALF_BIT_CYCLE;
        else
            pcjr_phase_count <= pcjr_phase_count - 16'd1;
    end

    // Determine current bit value based on position in frame
    // Frame structure (42 half-bits):
    //   [0-1]:   Start bit = 1 -> transmit [1,0]
    //   [2-17]:  Data bits (8 bits, LSB first) -> each bit transmits [value, ~value]
    //   [18-19]: Parity bit -> transmit [parity, ~parity]
    //   [20-41]: Stop bits (11 bits) = 0 -> all zeros
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            pcjr_current_bit <= 1'b0;
        else if (pcjr_sending) begin
            case (pcjr_half_bit_pos)
                // Start bit: [1, 0]
                6'd0:  pcjr_current_bit <= 1'b1;
                6'd1:  pcjr_current_bit <= 1'b0;
                // Data bit 0 (LSB)
                6'd2:  pcjr_current_bit <= pcjr_scancode[0];
                6'd3:  pcjr_current_bit <= ~pcjr_scancode[0];
                // Data bit 1
                6'd4:  pcjr_current_bit <= pcjr_scancode[1];
                6'd5:  pcjr_current_bit <= ~pcjr_scancode[1];
                // Data bit 2
                6'd6:  pcjr_current_bit <= pcjr_scancode[2];
                6'd7:  pcjr_current_bit <= ~pcjr_scancode[2];
                // Data bit 3
                6'd8:  pcjr_current_bit <= pcjr_scancode[3];
                6'd9:  pcjr_current_bit <= ~pcjr_scancode[3];
                // Data bit 4
                6'd10: pcjr_current_bit <= pcjr_scancode[4];
                6'd11: pcjr_current_bit <= ~pcjr_scancode[4];
                // Data bit 5
                6'd12: pcjr_current_bit <= pcjr_scancode[5];
                6'd13: pcjr_current_bit <= ~pcjr_scancode[5];
                // Data bit 6
                6'd14: pcjr_current_bit <= pcjr_scancode[6];
                6'd15: pcjr_current_bit <= ~pcjr_scancode[6];
                // Data bit 7 (MSB / break flag)
                6'd16: pcjr_current_bit <= pcjr_scancode[7];
                6'd17: pcjr_current_bit <= ~pcjr_scancode[7];
                // Parity bit (odd parity)
                6'd18: pcjr_current_bit <= pcjr_parity;
                6'd19: pcjr_current_bit <= ~pcjr_parity;
                // Stop bits (positions 20-41): all zeros
                default: pcjr_current_bit <= 1'b0;
            endcase
        end
        else begin
            pcjr_current_bit <= 1'b0;
        end
    end

    // Output keyboard data signal
    // Note: pcjr_keybd_in = ~pcjr_kbd_data, so we invert here
    // When sending: output inverted current bit value
    // When idle: output HIGH (1) -> pcjr_keybd_in will be LOW (idle state)
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            pcjr_kbd_data <= 1'b1;
        else if (pcjr_sending)
            pcjr_kbd_data <= ~pcjr_current_bit;
        else
            pcjr_kbd_data <= 1'b1;
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            prev_keybord_irq <= 1'b0;
            prev_pcjr_keybd_in <= 1'b1;
            keybd_latch      <= 1'b0;
        end
        else
        begin
            prev_keybord_irq <= keybord_irq;
            prev_pcjr_keybd_in <= pcjr_keybd_in;
            if (nmi_mask_register && (~io_read_n))
                keybd_latch <= 1'b0;
            else if (~prev_pcjr_keybd_in & pcjr_keybd_in)
                keybd_latch <= 1'b1;
            else
                keybd_latch <= keybd_latch;
        end
    end

    assign nmi_to_cpu = pcjr_nmi_enable & keybd_latch;


    // Keyboard reset
    KFPS2KB_Send_Data u_KFPS2KB_Send_Data 
    (
        // Bus
        .clock                      (clock),
        .peripheral_clock           (peripheral_clock),
        .reset                      (reset),

        // PS/2 I/O
        .device_clock               (ps2_clock),
        .device_clock_out           (ps2_send_clock),
        .device_data_out            (ps2_data_out),
        .sending_data_flag          (lock_recv_clock),

        // I/O
        .send_request               (~prev_ps2_reset_n & ps2_reset_n),
        .send_data                  (8'hFF)
    );

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            ps2_clock_out = 1'b1;
        else
            ps2_clock_out = ~(keybord_irq | ~ps2_send_clock | ~ps2_reset_n);
    end

    always_ff @(posedge clk_vga_cga)
    begin
        swap_video_buffer_2 <= swap_video_buffer_1;
        swap_video          <= swap_video_buffer_2;
    end


    assign jtopl2_snd_e = 16'd0;

    reg clk_en_opl2;
    always @(posedge clock) begin
        reg [27:0] sum = 0;

        clk_en_opl2 <= 0;
        sum = sum + 28'd3579545;
        if(sum >= clk_rate) begin
            sum = sum - clk_rate;
            clk_en_opl2 <= 1;
        end
    end

    wire [10:0] tandy_snd_e_int;
    wire        tandy_snd_rdy_int;
    assign tandy_snd_e = tandy_snd_e_int;
    assign tandy_snd_rdy = tandy_snd_rdy_int;

    // Tandy sound
		 jt89 sn76489
    (
        .rst(reset),
		  .clk(clock),
		  .clk_en(clk_en_opl2), // 3.579MHz
		  .wr_n(io_write_n),
		  .cs_n(tandy_chip_select_n),
		  .din(internal_data_bus),
		  .sound(tandy_snd_e_int),
		  .ready(tandy_snd_rdy_int)
    );
	 
//------------------------------------------------------------------------------

reg ce_1us;
always @(posedge clock) begin
	reg [27:0] sum = 0;

	ce_1us <= 0;
	sum = sum + 28'd1000000;
	if(sum >= clk_rate) begin
		sum = sum - clk_rate;
		ce_1us <= 1;
	end
end	 
	 
//------------------------------------------------------------------------------ c/ms

    always_comb begin
        o_cms_l = 16'd0;
        o_cms_r = 16'd0;
    end

//

    logic   keybord_interrupt_ff;
    logic   uart_interrupt_ff;
    logic   uart2_interrupt_ff;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            keybord_interrupt_ff    <= 1'b0;
            keybord_interrupt       <= 1'b0;
            uart_interrupt_ff       <= 1'b0;
            uart_interrupt          <= 1'b0;
            uart2_interrupt_ff      <= 1'b0;
            uart2_interrupt         <= 1'b0;
        end
        else
        begin
            keybord_interrupt_ff    <= 1'b0;
            keybord_interrupt       <= 1'b0;
            uart_interrupt_ff       <= uart_irq;
            uart_interrupt          <= uart_interrupt_ff;
            uart2_interrupt_ff      <= uart2_irq;
            uart2_interrupt         <= uart2_interrupt_ff;
        end
    end

    logic prev_io_read_n;
    logic prev_io_write_n;
    logic [7:0] write_to_uart;
    logic [7:0] write_to_uart2;
    logic [7:0] uart_readdata_1;
    logic [7:0] uart_readdata;
    logic [7:0] uart2_readdata_1;
    logic [7:0] uart2_readdata;

    always_ff @(posedge clock)
    begin
        prev_io_read_n <= io_read_n;
        prev_io_write_n <= io_write_n;
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            prev_nmi_mask_write_n <= 1'b1;
        else
            prev_nmi_mask_write_n <= nmi_mask_write_n;
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
        begin
            pcjr_nmi_enable <= 1'b0;
            ir_test_enable  <= 1'b0;
        end
        else if (write_nmi_mask)
        begin
            pcjr_nmi_enable <= internal_data_bus[7];
            ir_test_enable  <= internal_data_bus[6];
        end
    end

    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)
            port_a_in   <= 8'hFF;
        else
            port_a_in   <= 8'hFF;
    end

    reg [7:0] lpt_reg = 8'hFF;
	 reg [7:0] lpt_ctrl = 8'h00;
	 reg [7:0] lpt_enable_irq = 8'h00;
    reg [7:0] tandy_page_data = 8'h00;
    reg [7:0] nmi_mask_register_data = 8'hFF;
    always_ff @(posedge clock, posedge reset)
    begin
        if (reset)        
        begin
            xtctl <= 8'b00;
            tandy_page_data <= 8'h00;
            nmi_mask_register_data <= 8'hFF;
        end
        else begin
            if (~io_write_n)
            begin
                write_to_uart <= internal_data_bus;
                write_to_uart2 <= internal_data_bus;
            end
            else
            begin
                write_to_uart <= write_to_uart;
                write_to_uart2 <= write_to_uart2;
            end

            if ((lpt_chip_select) && (~io_write_n) && ~address[0])
                lpt_reg <= internal_data_bus;

            if ((lpt_ctrl_select) && (~io_write_n))
            begin
                lpt_ctrl <= internal_data_bus;
                lpt_enable_irq <= internal_data_bus & 8'h10;
            end

            if ((xtctl_chip_select) && (~io_write_n))
                xtctl <= internal_data_bus;

            if (tandy_page_chip_select && (~io_write_n))
                tandy_page_data <= internal_data_bus;

            if (write_nmi_mask)
                nmi_mask_register_data <= internal_data_bus;
        end

    end

    wire iorq_uart = (io_write_n & ~prev_io_write_n) || (~io_read_n  & prev_io_read_n);
    wire uart_tx;
    wire rts_n;
	 
    uart uart1
    (
        .clk               (clock),
        .br_clk            (clk_uart),
        .reset             (reset),

        .address           (address[2:0]),
        .writedata         (write_to_uart),
        .read              (~io_read_n  & prev_io_read_n),
        .write             (io_write_n & ~prev_io_write_n),
        .readdata          (uart_readdata_1),
        .cs                (uart_chip_select & iorq_uart),
        .rx                (uart_tx),
        .cts_n             (0),
        .dcd_n             (0),
        .dsr_n             (0),
        .ri_n              (1),
        .rts_n             (rts_n),
        .irq               (uart_irq)
    );
	 

    uart uart2
    (
        .clk               (clock),
        .br_clk            (clk_uart),
        .reset             (reset),

        .address           (address[2:0]),
        .writedata         (write_to_uart2),
        .read              (~io_read_n  & prev_io_read_n),
        .write             (io_write_n & ~prev_io_write_n),
        .readdata          (uart2_readdata_1),
        .cs                (uart2_chip_select & iorq_uart),

        .rx                (uart2_rx),
        .tx                (uart2_tx),
        .cts_n             (uart2_cts_n),
        .dcd_n             (uart2_dcd_n),
        .dsr_n             (uart2_dsr_n),
        .rts_n             (uart2_rts_n),
        .dtr_n             (uart2_dtr_n),
        .ri_n              (1),

        .irq               (uart2_irq)
    );
	 
    MSMouseWrapper MSMouseWrapper_inst 
    (
        .clk(clock),
        .ps2dta_in(ps2_mousedat_in),
        .ps2clk_in(ps2_mouseclk_in),
        .ps2dta_out(ps2_mousedat_out),
        .ps2clk_out(ps2_mouseclk_out),
        .rts(~rts_n),
        .rd(uart_tx)
    );

    // Timing of the readings may need to be reviewed.
    always_ff @(posedge clock)
    begin
        if (~io_read_n)
        begin
            uart_readdata <= uart_readdata_1;
            uart2_readdata <= uart2_readdata_1;
        end
        else
        begin
            uart_readdata <= uart_readdata;
            uart2_readdata <= uart2_readdata;
        end
    end


    logic  [16:0]  video_ram_address;
    logic  [7:0]   video_ram_data;
    logic          video_memory_write_n;
    logic          cga_mem_select_1;
    logic          video_mem_select_1;
    logic  [14:0]  video_io_address;
    logic  [7:0]   video_io_data;
    logic          video_io_write_n;
    logic          video_io_read_n;
    logic          video_address_enable_n;
    logic  [14:0]  cga_io_address_1;
    logic  [14:0]  cga_io_address_2;
    logic  [7:0]   cga_io_data_1;
    logic  [7:0]   cga_io_data_2;
    logic          cga_io_write_n_1;
    logic          cga_io_write_n_2;
    logic          cga_io_read_n_1;
    logic          cga_io_read_n_2;
    logic          cga_address_enable_n_1;
    logic          cga_address_enable_n_2;
    localparam int SPLASH_COPY_SIZE = 4000;
    localparam int TEXT_CLEAR_SIZE = 131072;
    localparam [11:0] SPLASH_COPY_LAST = SPLASH_COPY_SIZE - 1;
    localparam [16:0] TEXT_CLEAR_LAST = TEXT_CLEAR_SIZE - 1;
    logic         splashscreen_ff = 1'b0;
    logic         splash_copy_active = 1'b0;
    logic [11:0]  splash_copy_addr = 12'd0;
    logic         splash_clear_active = 1'b0;
    logic         splash_clear_pending = 1'b0;
    logic [16:0]  splash_clear_addr = 17'd0;
    wire          splash_copy_start = splashscreen & ~splashscreen_ff;
    wire          splash_clear_start = ~splashscreen & splashscreen_ff;
    wire          status0_clear_start = status0_clear;
    wire  [7:0]   splash_rom_data;
    wire          cga_vram_copy = splash_copy_active | splash_clear_active;
    wire  [7:0]   splash_clear_data = 8'h00;

    always_ff @(posedge clock)
    begin
        if (~io_write_n | ~io_read_n)
        begin
            video_io_address    <= address[13:0];
            video_io_data       <= internal_data_bus;
        end
        else
        begin
            video_io_address    <= video_io_address;
            video_io_data       <= video_io_data;
        end
    end

    always_ff @(posedge clock)
    begin
        video_ram_address       <= address[16:0];
        video_ram_data          <= internal_data_bus;
        video_memory_write_n    <= memory_write_n;
        cga_mem_select_1        <= cga_mem_select;
        video_mem_select_1      <= video_mem_select;

        video_io_write_n        <= io_write_n;
        video_io_read_n         <= io_read_n;
        video_address_enable_n  <= address_enable_n;
    end

    always_ff @(posedge clock)
    begin
        splashscreen_ff <= splashscreen;

        if (splash_copy_start)
        begin
            splash_copy_active <= 1'b1;
            splash_copy_addr   <= 12'd0;
        end
        else if (splash_copy_active)
        begin
            if (splash_copy_addr == SPLASH_COPY_LAST)
            begin
                splash_copy_active <= 1'b0;
                splash_copy_addr   <= 12'd0;
            end
            else
            begin
                splash_copy_addr <= splash_copy_addr + 12'd1;
            end
        end
        else
        begin
            splash_copy_active <= 1'b0;
            splash_copy_addr   <= 12'd0;
        end

        if (splash_clear_start || status0_clear_start)
            splash_clear_pending <= 1'b1;

        if (~splash_copy_active && splash_clear_pending && ~splash_clear_active && ~splashscreen)
        begin
            splash_clear_active  <= 1'b1;
            splash_clear_pending <= 1'b0;
            splash_clear_addr    <= 17'd0;
        end
        else if (splash_clear_active)
        begin
            if (splash_clear_addr == TEXT_CLEAR_LAST)
            begin
                splash_clear_active <= 1'b0;
                splash_clear_addr   <= 17'd0;
            end
            else
            begin
                splash_clear_addr <= splash_clear_addr + 17'd1;
            end
        end
        else
        begin
            splash_clear_active <= 1'b0;
            splash_clear_addr   <= 17'd0;
        end
    end

    always_ff @(posedge clk_vga_cga)
    begin
        cga_io_address_1        <= video_io_address;
        cga_io_address_2        <= cga_io_address_1;
        cga_io_data_1           <= video_io_data;
        cga_io_data_2           <= cga_io_data_1;
        cga_io_write_n_1        <= video_io_write_n;
        cga_io_write_n_2        <= cga_io_write_n_1;
        cga_io_read_n_1         <= video_io_read_n;
        cga_io_read_n_2         <= cga_io_read_n_1;
        cga_address_enable_n_1  <= video_address_enable_n;
        cga_address_enable_n_2  <= cga_address_enable_n_1;
    end


    reg   [5:0]   R_CGA;
    reg   [5:0]   G_CGA;
    reg   [5:0]   B_CGA;
    reg           HSYNC_CGA;
    reg           VSYNC_CGA;
    logic         vsync_sync_1;
    logic         vsync_sync_2;
    logic         video_irq;
    reg           HBLANK_CGA;
    reg           VBLANK_CGA;
    reg           de_o_cga;

    wire [3:0] video_cga;
    assign VGA_R = R_CGA;
    assign VGA_G = G_CGA;
    assign VGA_B = B_CGA;
    assign VGA_HSYNC = HSYNC_CGA;
    assign VGA_VSYNC = VSYNC_CGA;
    // PCjr generates IRQ5 while vertical retrace is active (level).
    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            vsync_sync_1 <= 1'b0;
            vsync_sync_2 <= 1'b0;
        end else begin
            vsync_sync_1 <= VSYNC_CGA;
            vsync_sync_2 <= vsync_sync_1;
        end
    end

    assign video_irq = vsync_sync_2;
    assign VGA_HBlank = HBLANK_CGA;
    assign VGA_VBlank = VBLANK_CGA;
    assign de_o = de_o_cga;


    wire CGA_VRAM_ENABLE;
    wire [18:0] CGA_VRAM_ADDR;
    wire [7:0] CGA_VRAM_DOUT;
    wire        CGA_CRTC_OE;
    logic       CGA_CRTC_OE_1;
    logic       CGA_CRTC_OE_2;
    wire [7:0]  CGA_CRTC_DOUT;
    logic [7:0] CGA_CRTC_DOUT_1;
    logic [7:0] CGA_CRTC_DOUT_2;
    wire        VGA_VBlank_border_raw;
    wire        std_hsyncwidth_raw;
    wire        tandy_color_16_raw;

    // Sets up the card to generate a video signal
    // that will work with a standard VGA monitor
    // connected to the VGA port.

    // wire composite_on;
    wire thin_font;

    // Composite mode switch
    //assign composite_on = switch3; (TODO: Test in next version, from the original Graphics Gremlin sources)

    // Thin font switch (TODO: switchable with Keyboard shortcut)
    assign thin_font = 1'b0; // Default: No thin font

    wire composite_cga = tandy_video_en ? (swap_video ? ~composite : composite) : composite;

    assign VGA_VBlank_border = VGA_VBlank_border_raw;
    assign std_hsyncwidth = std_hsyncwidth_raw;
    assign tandy_color_16 = tandy_color_16_raw;


    // CGA digital to analog converter
    cga_vgaport vga_cga 
    (
        .clk(clk_vga_cga),
        .clkdiv(clkdiv),
        .video(video_cga),
        .hblank(HBLANK_CGA),
        .composite(composite_cga),
        .red(R_CGA),
        .green(G_CGA),
        .blue(B_CGA)
    );

    cga cga1 
    (
        .clk                        (clk_vga_cga),
        .clkdiv                     (clkdiv),
        .bus_a                      (cga_io_address_2),
        .bus_ior_l                  (cga_io_read_n_2),
        .bus_iow_l                  (cga_io_write_n_2),
        .bus_memr_l                 (1'd0),
        .bus_memw_l                 (1'd0),
        .bus_d                      (cga_io_data_2),
        .bus_out                    (CGA_CRTC_DOUT),
        .bus_dir                    (CGA_CRTC_OE),
        .bus_aen                    (cga_address_enable_n_2),
        .ram_we_l                   (CGA_VRAM_ENABLE),
        .ram_a                      (CGA_VRAM_ADDR),
        .ram_d                      (CGA_VRAM_DOUT),
        .hsync                      (HSYNC_CGA),              // non scandoubled
    //  .dbl_hsync                  (HSYNC_CGA),              // scandoubled
        .hblank                     (HBLANK_CGA),
        .vsync                      (VSYNC_CGA),
        .vblank                     (VBLANK_CGA),
        .vblank_border              (VGA_VBlank_border_raw),
        .std_hsyncwidth             (std_hsyncwidth_raw),
        .de_o                       (de_o_cga),
        .video                      (video_cga),              // non scandoubled
    //  .dbl_video                  (video_cga),              // scandoubled
        .splashscreen               (splashscreen),
        .thin_font                  (thin_font),
        .tandy_video                (tandy_video_en),
        .pcjr_addr_mode             (pcjr_addr_mode),
        .grph_mode                  (grph_mode),
        .hres_mode                  (hres_mode),
        .tandy_color_16             (tandy_color_16_raw),
        .cga_hw                     (cga_hw),
        .crt_h_offset               (crt_h_offset),
        .crt_v_offset               (crt_v_offset)
    );

    always_ff @(posedge clock)
    begin
        CGA_CRTC_OE_1   <= CGA_CRTC_OE;
        CGA_CRTC_OE_2   <= CGA_CRTC_OE_1;
        CGA_CRTC_DOUT_1 <= CGA_CRTC_DOUT;
        CGA_CRTC_DOUT_2 <= CGA_CRTC_DOUT_1;
    end


    defparam cga1.BLINK_MAX = 24'd4772727;
    wire [7:0] cga_vram_cpu_dout;

    splash_rom splash_rom_inst
    (
        .addr       (splash_copy_addr),
        .data       (splash_rom_data)
    );

    wire [16:0] cga_copy_addr  = splash_copy_active ? {5'd0, splash_copy_addr} : splash_clear_addr;
    wire [7:0]  cga_copy_data  = splash_copy_active ? splash_rom_data : splash_clear_data;
    wire [16:0] cga_vram_addra = cga_vram_copy ? cga_copy_addr :
                                 (tandy_video_en ? (video_mem_select_1 ? video_ram_address :
                                 (pcjr_memctrl_32k ? {pcjr_b8000_page[1:0], video_ram_address[14:0]} :
                                 {pcjr_b8000_page, video_ram_address[13:0]})) : {3'b000, video_ram_address[13:0]});
    wire [16:0] cga_vram_addrb = tandy_video_en ?
                                 (pcjr_memctrl_32k ? {pcjr_vram_page[1:0], CGA_VRAM_ADDR[14:0]} :
                                 {pcjr_vram_page, CGA_VRAM_ADDR[13:0]}) : {3'b000, CGA_VRAM_ADDR[13:0]};
    wire [7:0]  cga_vram_dina  = cga_vram_copy ? cga_copy_data : video_ram_data;
    wire        cga_vram_ena   = cga_vram_copy ? 1'b1 : (cga_mem_select_1 || video_mem_select_1);
    wire        cga_vram_wea   = cga_vram_copy ? 1'b1 : (~video_memory_write_n & memory_write_n);
    wire        cga_vram_enb   = CGA_VRAM_ENABLE;

    vram #(.AW(17)) cga_vram
    (
        .clka                       (clock),
        .ena                        (cga_vram_ena),
        .wea                        (cga_vram_wea),
        .addra                      (cga_vram_addra),
        .dina                       (cga_vram_dina),
        .douta                      (cga_vram_cpu_dout),
        .clkb                       (clk_vga_cga),
        .web                        (1'b0),
        .enb                        (cga_vram_enb),
        .addrb                      (cga_vram_addrb),
        .dinb                       (8'h0),
        .doutb                      (CGA_VRAM_DOUT)
    );

    //
    // FDC
    //
    logic           mgmt_fdd_cs;
    logic   [15:0]  mgmt_fdd_readdata;
    logic   [7:0]   write_to_fdd;
    logic   [2:0]   fdd_io_address;
    logic           fdd_io_read;
    logic           fdd_io_read_1;
    logic           fdd_io_write;
    logic   [7:0]   fdd_readdata_wire;
    logic   [7:0]   fdd_dma_readdata;
    logic   [7:0]   fdd_readdata;
    logic           fdd_dma_req_wire;
    logic           fdd_dma_read;
    logic           prev_fdd_dma_ack;
    logic           fdd_dma_rw_ack;
    logic           fdd_dma_tc;

    assign  mgmt_fdd_cs = (mgmt_address[15:8] == 8'hF2);

    always_ff @(posedge clock)
    begin
        if (mgmt_write & mgmt_fdd_cs & (mgmt_address[3:0] == 4'd0))
            fdd_present[mgmt_address[7]] <= mgmt_writedata[0];
    end

    always_ff @(posedge clock)
    begin
        if (~io_write_n)
            write_to_fdd  <= internal_data_bus;
        else
            write_to_fdd  <= write_to_fdd;
    end

    always_ff @(posedge clock)
    begin
        fdd_io_address     <= address[2:0];
        fdd_io_read        <= ~io_read_n & prev_io_read_n   & ~floppy0_chip_select_n;
        fdd_io_read_1      <= fdd_io_read;
        fdd_io_write       <= io_write_n & ~prev_io_write_n & ~floppy0_chip_select_n;
    end

    assign  fdd_dma_read    = fdd_dma_ack & ~io_read_n;

    always_ff @(posedge clock)
    begin
        prev_fdd_dma_ack   <= fdd_dma_ack;
    end

    assign  fdd_dma_rw_ack  = prev_fdd_dma_ack & ~fdd_dma_ack;

    always_ff @(posedge clock)
    begin
        if (fdd_dma_ack)
            if (fdd_dma_tc == 1'b0)
                fdd_dma_tc <= terminal_count;
            else
                fdd_dma_tc <= fdd_dma_tc;
        else
            fdd_dma_tc <= 1'b0;
    end

    floppy floppy 
    (
        .clk                        (clock),
        .rst_n                      (~reset),
        .pcjr_mode                  (1'b1),

        //dma
        .dma_req                    (fdd_dma_req_wire),
        .dma_ack                    (fdd_dma_rw_ack),
        .dma_tc                     (fdd_dma_tc & fdd_dma_rw_ack),
        .dma_readdata               (write_to_fdd),
        .dma_writedata              (fdd_dma_readdata),

        //irq
        .irq                        (fdd_interrupt),

        //io buf
        .io_address                 (fdd_io_address),
        .io_read                    (fdd_io_read),
        .io_readdata                (fdd_readdata_wire),
        .io_write                   (fdd_io_write),
        .io_writedata               (write_to_fdd),

        //        .fdd0_inserted              (),

        .mgmt_address               (mgmt_address[3:0]),
        .mgmt_fddn                  (mgmt_address[7]),
        .mgmt_write                 (mgmt_write & mgmt_fdd_cs),
        .mgmt_writedata             (mgmt_writedata),
        .mgmt_read                  (mgmt_read  & mgmt_fdd_cs),
        .mgmt_readdata              (mgmt_fdd_readdata),

        .wp                         (floppy_wp),

        .clock_rate                 (clk_select[1] == 1'b0 ? clk_rate :
                                     clk_select[0] == 1'b0 ? {1'b0, clk_rate[27:1]} : {2'b00, clk_rate[27:2]}),

        .request                    (fdd_request)
    );

    always_ff @(posedge clock)
    begin
        if (fdd_dma_ack)
            fdd_dma_req <= 1'b0;
        else if (cpu_clock_negedge)
            fdd_dma_req <= fdd_dma_req_wire;
        else
            fdd_dma_req <= fdd_dma_req;
    end

    always_ff @(posedge clock)
    begin
        if ((fdd_io_read_1) && (~address_enable_n))
            fdd_readdata <= fdd_readdata_wire;
        else if (fdd_dma_read)
            fdd_readdata <= fdd_dma_readdata;
        else
            fdd_readdata <= fdd_readdata;
    end


    //
    // mgmt_readdata
    //
    assign mgmt_readdata = mgmt_fdd_readdata;


    //
    // KFTVGA
    //
    
    // logic   [7:0]   tvga_data_bus_out;

    // KFTVGA u_KFTVGA (
    //     // Bus
    //     .clock                      (clock),
    //     .reset                      (reset),
    //     .chip_select_n              (tvga_chip_select_n),
    //     .read_enable_n              (memory_read_n),
    //     .write_enable_n             (memory_write_n),
    //     .address                    (address[13:0]),
    //     .data_bus_in                (internal_data_bus),
    //     .data_bus_out               (tvga_data_bus_out),

    //     // I/O
    //     .video_clock                (video_clock),
    //     .video_reset                (video_reset),
    //     .video_h_sync               (video_h_sync),
    //     .video_v_sync               (video_v_sync),
    //     .video_r                    (video_r),
    //     .video_g                    (video_g),
    //     .video_b                    (video_b)
    // );

	 
    // RTC
	 
    logic           mgmt_rtc_cs;
    logic   [7:0]   rtc_readdata;
	 
    assign mgmt_rtc_cs   = (mgmt_address[15:8] == 8'hF4);

    rtc rtc
    (
       .clk               (clock),
       .rst_n             (~reset),

       .clock_rate        (clk_rate),

       .io_address        (address[0]),
       .io_writedata      (internal_data_bus),
       .io_read           (~io_read_n & rtc_chip_select),
       .io_write          (~io_write_n & rtc_chip_select),
       .io_readdata       (rtc_readdata),

       .mgmt_address      (mgmt_address),
       .mgmt_write        (mgmt_write & mgmt_rtc_cs),
       .mgmt_writedata    (mgmt_writedata[7:0]),

       .memcfg            (1'b0),
       .bootcfg           (5'd0)
    );
    

    //
    // Joysticks
    //

    logic [7:0] joy_data;

    tandy_pcjr_joy joysticks
    (
        .clk                       (clock),
        .reset                     (reset),
        .en                        (joystick_select && ~io_write_n),
        .clk_select                (clk_select),
        .joy_opts                  (joy_opts),
        .joy0                      (joy0),
        .joy1                      (joy1),
        .joya0                     (joya0),
        .joya1                     (joya1),
        .d_out                     (joy_data)
    );


    //
    // data_bus_out
    //
    
    always_ff @(posedge clock)
    begin
        if (~interrupt_acknowledge_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= interrupt_data_bus_out;
        end
        else if ((~interrupt_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= interrupt_data_bus_out;
        end
        else if ((~timer_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= timer_data_bus_out;
        end
        else if ((~ppi_chip_select_n) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= ppi_data_bus_out;
        end
        else if ((cga_mem_select || video_mem_select) && (~memory_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= cga_vram_cpu_dout;
        end
        else if (CGA_CRTC_OE_2)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= CGA_CRTC_DOUT_2;
        end
        else if ((uart_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= uart_readdata;
        end
        else if ((uart2_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= uart2_readdata;
        end
        else if ((lpt_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= address[0] ? 8'hDF : lpt_reg;
        end
        else if ((lpt_ctrl_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= 8'hE0 | lpt_ctrl | lpt_enable_irq;
        end
        else if ((xtctl_chip_select) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= xtctl;
        end
        else if (nmi_mask_register && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= nmi_mask_register_data;
        end
        else if (joystick_select && ~io_read_n)
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= joy_data;
        end
        else if ((~floppy0_chip_select_n || fdd_dma_read) && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= fdd_readdata;
        end
        else if (rtc_chip_select && (~io_read_n))
        begin
            data_bus_out_from_chipset <= 1'b1;
            data_bus_out <= rtc_readdata;
        end
        else
        begin
            data_bus_out_from_chipset <= 1'b0;
            data_bus_out <= 8'b00000000;
        end
    end

endmodule
