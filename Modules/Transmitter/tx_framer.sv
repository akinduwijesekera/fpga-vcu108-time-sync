`timescale 1ns/1ps

module tx_framer (
    input  logic clk,
    input  logic rst_n,

    input  logic [47:0] dst_mac,
    input  logic [47:0] src_mac,
    input  logic [15:0] ether_type,

    axi_stream_if.slave  s_axis, // payload in (from packet_tx)
    axi_stream_if.master m_axis, // framed out

    output logic fr_busy,
    output logic fr_done
);

    wire s_fire = s_axis.tvalid && s_axis.tready;
    wire m_fire = m_axis.tvalid && m_axis.tready;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_CAP1,
        ST_CAP2,
        ST_SEND0,
        ST_SEND1,
        ST_SEND2,
        ST_SEND3,
        ST_SEND4
    } state_t;

    state_t st, st_n;

    logic [47:0] dst_l, src_l;
    logic [15:0] etype_l;

    // Payload storage: 20 bytes
    logic [7:0] payload [0:19];
    logic [5:0] cap_count; // 0..20

    logic fr_done_r;
    assign fr_done = fr_done_r;

    function automatic logic [63:0] pack8(
        input logic [7:0] b0, b1, b2, b3, b4, b5, b6, b7
    );
        pack8 = {b7,b6,b5,b4,b3,b2,b1,b0};
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= ST_IDLE;
            cap_count <= 6'd0;
            dst_l     <= 48'd0;
            src_l     <= 48'd0;
            etype_l   <= 16'd0;
            fr_done_r <= 1'b0;
        end else begin
            st <= st_n;

            fr_done_r <= 1'b0;

            if (st == ST_IDLE && s_fire) begin
                dst_l   <= dst_mac;
                src_l   <= src_mac;
                etype_l <= ether_type;
            end

            if ((st == ST_IDLE || st == ST_CAP1 || st == ST_CAP2) && s_fire) begin
                int unsigned k;
                int i;

                if (st == ST_IDLE)
                    k = 0;
                else
                    k = cap_count;

                for (i = 0; i < 8; i++) begin
                    if (k < 20 && s_axis.tkeep[i]) begin
                        payload[k] <= s_axis.tdata[8*i +: 8];
                        k++;
                    end
                end

                cap_count <= k[5:0];
            end

            if (st == ST_SEND4 && m_fire) begin
                fr_done_r <= 1'b1;
            end
        end
    end

    always_comb begin
        st_n = st;

        s_axis.tready = 1'b0;

        m_axis.tvalid = 1'b0;
        m_axis.tdata  = 64'd0;
        m_axis.tkeep  = 8'h00;
        m_axis.tlast  = 1'b0;

        fr_busy = 1'b0;

        unique case (st)
            ST_IDLE: begin
                s_axis.tready = 1'b1;
                if (s_fire) st_n = ST_CAP1;
            end

            ST_CAP1: begin
                fr_busy = 1'b1;
                s_axis.tready = 1'b1;
                if (s_fire) st_n = ST_CAP2;
            end

            ST_CAP2: begin
                fr_busy = 1'b1;
                s_axis.tready = 1'b1;
                if (s_fire) st_n = ST_SEND0;
            end

            ST_SEND0: begin
                fr_busy = 1'b1;
                m_axis.tvalid = 1'b1;
                m_axis.tkeep  = 8'hFF;

                // Bytes 0..7: Dst[0..5], Src[0..1]
                m_axis.tdata = pack8(
                    dst_l[47:40], dst_l[39:32], dst_l[31:24], dst_l[23:16],
                    dst_l[15:8],  dst_l[7:0],   src_l[47:40], src_l[39:32]
                );

                if (m_fire) st_n = ST_SEND1;
            end

            ST_SEND1: begin
                fr_busy = 1'b1;
                m_axis.tvalid = 1'b1;
                m_axis.tkeep  = 8'hFF;

                // Bytes 8..15: Src[2..5], EtherType[1:0], Payload[0..1]
                m_axis.tdata = pack8(
                    src_l[31:24], src_l[23:16], src_l[15:8], src_l[7:0],
                    etype_l[15:8], etype_l[7:0],
                    payload[0], payload[1]
                );

                if (m_fire) st_n = ST_SEND2;
            end

            ST_SEND2: begin
                fr_busy = 1'b1;
                m_axis.tvalid = 1'b1;
                m_axis.tkeep  = 8'hFF;

                // Bytes 16..23: Payload[2..9]
                m_axis.tdata = pack8(
                    payload[2], payload[3], payload[4], payload[5],
                    payload[6], payload[7], payload[8], payload[9]
                );

                if (m_fire) st_n = ST_SEND3;
            end

            ST_SEND3: begin
                fr_busy = 1'b1;
                m_axis.tvalid = 1'b1;
                m_axis.tkeep  = 8'hFF;

                // Bytes 24..31: Payload[10..17]
                m_axis.tdata = pack8(
                    payload[10], payload[11], payload[12], payload[13],
                    payload[14], payload[15], payload[16], payload[17]
                );

                if (m_fire) st_n = ST_SEND4;
            end

            ST_SEND4: begin
                fr_busy = 1'b1;
                m_axis.tvalid = 1'b1;
                m_axis.tkeep  = 8'h03;
                m_axis.tlast  = 1'b1;

                // Bytes 32..33: Payload[18..19]
                m_axis.tdata = {
                    48'h000000000000,
                    payload[19],
                    payload[18]
                };

                if (m_fire) st_n = ST_IDLE;
            end

            default: begin
                st_n = ST_IDLE;
            end
        endcase
    end

endmodule
