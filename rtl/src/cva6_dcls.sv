// Copyright 2026 ETH Zurich, University of Bologna, Fondazione Chips-IT, OpenHW Group
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

`include "rvfi_types.svh"
`include "cvxif_types.svh"
`include "hpdcache_typedef.svh"

module cva6_dcls
  import ariane_pkg::*;
#(
    // Top configurations
    parameter bit EnableDMR = 1'b1,
    parameter bit EnableHMR = 1'b0,

    localparam int unsigned NumPhysicalCores = EnableDMR ? 2 : 1,
    localparam int unsigned NumLogicalCores  = EnableHMR ? NumPhysicalCores : 1,

    // CVA6 config
    parameter config_pkg::cva6_cfg_t CVA6Cfg = build_config_pkg::build_config(
        cva6_config_pkg::cva6_cfg
    ),

    // RVFI PROBES
    parameter type rvfi_probes_instr_t = `RVFI_PROBES_INSTR_T(CVA6Cfg),
    parameter type rvfi_probes_csr_t = `RVFI_PROBES_CSR_T(CVA6Cfg),
    parameter type rvfi_probes_t = struct packed {
      rvfi_probes_csr_t   csr;
      rvfi_probes_instr_t instr;
    },

    // branchpredict scoreboard entry
    // this is the struct which we will inject into the pipeline to guide the various
    // units towards the correct branch decision and resolve
    localparam type branchpredict_sbe_t = struct packed {
      cf_t                     cf;               // type of control flow prediction
      logic [CVA6Cfg.VLEN-1:0] predict_address;  // target address at which to jump, or not
    },

    parameter type exception_t = struct packed {
      logic [CVA6Cfg.XLEN-1:0] cause;  // cause of exception
      logic [CVA6Cfg.XLEN-1:0] tval;  // additional information of causing exception (e.g.: instruction causing it),
      // address of LD/ST fault
      logic [CVA6Cfg.GPLEN-1:0] tval2;  // additional information when the causing exception in a guest exception
      logic [31:0] tinst;  // transformed instruction information
      logic gva;  // signals when a guest virtual address is written to tval
      logic valid;
    },

    // cache request ports
    // I$ address translation requests
    localparam type icache_areq_t = struct packed {
      logic                    fetch_valid;      // address translation valid
      logic [CVA6Cfg.PLEN-1:0] fetch_paddr;      // physical address in
      exception_t              fetch_exception;  // exception occurred during fetch
    },
    localparam type icache_arsp_t = struct packed {
      logic                    fetch_req;    // address translation request
      logic [CVA6Cfg.VLEN-1:0] fetch_vaddr;  // virtual address out
    },

    // I$ data requests
    localparam type icache_dreq_t = struct packed {
      logic                    req;      // we request a new word
      logic                    kill_s1;  // kill the current request
      logic                    kill_s2;  // kill the last request
      logic                    spec;     // request is speculative
      logic [CVA6Cfg.VLEN-1:0] vaddr;    // 1st cycle: 12 bit index is taken for lookup
    },
    localparam type icache_drsp_t = struct packed {
      logic                                ready;  // icache is ready
      logic                                valid;  // signals a valid read
      logic [CVA6Cfg.FETCH_WIDTH-1:0]      data;   // 2+ cycle out: tag
      logic [CVA6Cfg.FETCH_USER_WIDTH-1:0] user;   // User bits
      logic [CVA6Cfg.VLEN-1:0]             vaddr;  // virtual address out
      exception_t                          ex;     // we've encountered an exception
    },

    // IF/ID Stage
    // store the decompressed instruction
    localparam type fetch_entry_t = struct packed {
      logic [CVA6Cfg.VLEN-1:0] address;  // the address of the instructions from below
      logic [31:0] instruction;  // instruction word
      branchpredict_sbe_t     branch_predict; // this field contains branch prediction information regarding the forward branch path
      exception_t             ex;             // this field contains exceptions which might have happened earlier, e.g.: fetch exceptions
    },
    //JVT struct{base,mode}
    localparam type jvt_t = struct packed {
      logic [CVA6Cfg.XLEN-7:0] base;
      logic [5:0] mode;
    },

    // ID/EX/WB Stage
    localparam type scoreboard_entry_t = struct packed {
      logic [CVA6Cfg.VLEN-1:0] pc;  // PC of instruction
      logic [CVA6Cfg.TRANS_ID_BITS-1:0] trans_id;      // this can potentially be simplified, we could index the scoreboard entry
      // with the transaction id in any case make the width more generic
      fu_t fu;  // functional unit to use
      fu_op op;  // operation to perform in each functional unit
      logic [REG_ADDR_SIZE-1:0] rs1;  // register source address 1
      logic [REG_ADDR_SIZE-1:0] rs2;  // register source address 2
      logic [REG_ADDR_SIZE-1:0] rd;  // register destination address
      logic [CVA6Cfg.XLEN-1:0] result;  // for unfinished instructions this field also holds the immediate,
      // for unfinished floating-point that are partly encoded in rs2, this field also holds rs2
      // for unfinished floating-point fused operations (FMADD, FMSUB, FNMADD, FNMSUB)
      // this field holds the address of the third operand from the floating-point register file
      logic valid;  // is the result valid
      logic use_imm;  // should we use the immediate as operand b?
      logic use_zimm;  // use zimm as operand a
      logic use_pc;  // set if we need to use the PC as operand a, PC from exception
      exception_t ex;  // exception has occurred
      branchpredict_sbe_t bp;  // branch predict scoreboard data structure
      logic                     is_compressed; // signals a compressed instructions, we need this information at the commit stage if
                                               // we want jump accordingly e.g.: +4, +2
      logic is_macro_instr;  // is an instruction executed as predefined sequence of instructions called macro definition
      logic is_last_macro_instr;  // is last decoded 32bit instruction of macro definition
      logic is_double_rd_macro_instr;  // is double move decoded 32bit instruction of macro definition
      logic vfp;  // is this a vector floating-point instruction?
      logic is_zcmt;  //is a zcmt instruction
    },
    localparam type writeback_t = struct packed {
      logic valid;  // wb data is valid
      logic [CVA6Cfg.XLEN-1:0] data;  //wb data
      logic ex_valid;  // exception from WB
      logic [CVA6Cfg.TRANS_ID_BITS-1:0] trans_id;  //transaction ID
    },

    // branch-predict
    // this is the struct we get back from ex stage and we will use it to update
    // all the necessary data structures
    // bp_resolve_t
    localparam type bp_resolve_t = struct packed {
      logic                    valid;           // prediction with all its values is valid
      logic [CVA6Cfg.VLEN-1:0] pc;              // PC of predict or mis-predict
      logic [CVA6Cfg.VLEN-1:0] target_address;  // target address at which to jump, or not
      logic                    is_mispredict;   // set if this was a mis-predict
      logic                    is_taken;        // branch is taken
      cf_t                     cf_type;         // Type of control flow change
    },

    // All information needed to determine whether we need to associate an interrupt
    // with the corresponding instruction or not.
    localparam type irq_ctrl_t = struct packed {
      logic [CVA6Cfg.XLEN-1:0] mie;
      logic [CVA6Cfg.XLEN-1:0] mip;
      logic [CVA6Cfg.XLEN-1:0] mideleg;
      logic [CVA6Cfg.XLEN-1:0] hideleg;
      logic                    sie;
      logic                    global_enable;
    },

    localparam type lsu_ctrl_t = struct packed {
      logic                             valid;
      logic [CVA6Cfg.VLEN-1:0]          vaddr;
      logic [31:0]                      tinst;
      logic                             hs_ld_st_inst;
      logic                             hlvx_inst;
      logic                             overflow;
      logic                             g_overflow;
      logic [CVA6Cfg.XLEN-1:0]          data;
      logic [(CVA6Cfg.XLEN/8)-1:0]      be;
      fu_t                              fu;
      fu_op                             operation;
      logic [CVA6Cfg.TRANS_ID_BITS-1:0] trans_id;
      logic                             is_speculative_load;
      logic                             is_speculative_load_miss;
    },


    localparam type cbo_t = logic [7:0],

    localparam type fu_data_t = struct packed {
      fu_t                              fu;
      fu_op                             operation;
      logic [CVA6Cfg.XLEN-1:0]          operand_a;
      logic [CVA6Cfg.XLEN-1:0]          operand_b;
      logic [CVA6Cfg.XLEN-1:0]          imm;
      logic [CVA6Cfg.TRANS_ID_BITS-1:0] trans_id;
    },

    localparam type icache_req_t = struct packed {
      logic [CVA6Cfg.ICACHE_SET_ASSOC_WIDTH-1:0] way;  // way to replace
      logic [CVA6Cfg.PLEN-1:0] paddr;  // physical address
      logic nc;  // noncacheable
      logic [CVA6Cfg.MEM_TID_WIDTH-1:0] tid;  // thread id (used as transaction id in Ariane)
    },
    localparam type icache_rtrn_t = struct packed {
      wt_cache_pkg::icache_in_t rtype;  // see definitions above
      logic [CVA6Cfg.ICACHE_LINE_WIDTH-1:0] data;  // full cache line width
      logic [CVA6Cfg.ICACHE_USER_LINE_WIDTH-1:0] user;  // user bits
      struct packed {
        logic                                      vld;  // invalidate only affected way
        logic                                      all;  // invalidate all ways
        logic [CVA6Cfg.ICACHE_INDEX_WIDTH-1:0]     idx;  // physical address to invalidate
        logic [CVA6Cfg.ICACHE_SET_ASSOC_WIDTH-1:0] way;  // way to invalidate
      } inv;  // invalidation vector
      logic [CVA6Cfg.MEM_TID_WIDTH-1:0] tid;  // thread id (used as transaction id in Ariane)
    },

    // D$ data requests
    localparam type dcache_req_i_t = struct packed {
      logic [CVA6Cfg.DCACHE_INDEX_WIDTH-1:0] address_index;
      logic [CVA6Cfg.DCACHE_TAG_WIDTH-1:0]   address_tag;
      logic [CVA6Cfg.XLEN-1:0]               data_wdata;
      logic [CVA6Cfg.DCACHE_USER_WIDTH-1:0]  data_wuser;
      logic                                  data_req;
      logic                                  data_we;
      logic [(CVA6Cfg.XLEN/8)-1:0]           data_be;
      logic [1:0]                            data_size;
      logic [CVA6Cfg.DcacheIdWidth-1:0]      data_id;
      logic                                  kill_req;
      logic                                  tag_valid;
      cbo_t                                  cbo_op;
    },

    localparam type dcache_req_o_t = struct packed {
      logic                                 data_gnt;
      logic                                 data_rvalid;
      logic [CVA6Cfg.DcacheIdWidth-1:0]     data_rid;
      logic [CVA6Cfg.XLEN-1:0]              data_rdata;
      logic [CVA6Cfg.DCACHE_USER_WIDTH-1:0] data_ruser;
    },

    // Accelerator - CVA6
    parameter type accelerator_req_t  = logic,
    parameter type accelerator_resp_t = logic,

    // Accelerator - CVA6's MMU
    parameter type acc_mmu_req_t  = logic,
    parameter type acc_mmu_resp_t = logic,

    // AXI types
    parameter type axi_ar_chan_t = struct packed {
      logic [CVA6Cfg.AxiIdWidth-1:0]   id;
      logic [CVA6Cfg.AxiAddrWidth-1:0] addr;
      axi_pkg::len_t                   len;
      axi_pkg::size_t                  size;
      axi_pkg::burst_t                 burst;
      logic                            lock;
      axi_pkg::cache_t                 cache;
      axi_pkg::prot_t                  prot;
      axi_pkg::qos_t                   qos;
      axi_pkg::region_t                region;
      logic [CVA6Cfg.AxiUserWidth-1:0] user;
    },
    parameter type axi_aw_chan_t = struct packed {
      logic [CVA6Cfg.AxiIdWidth-1:0]   id;
      logic [CVA6Cfg.AxiAddrWidth-1:0] addr;
      axi_pkg::len_t                   len;
      axi_pkg::size_t                  size;
      axi_pkg::burst_t                 burst;
      logic                            lock;
      axi_pkg::cache_t                 cache;
      axi_pkg::prot_t                  prot;
      axi_pkg::qos_t                   qos;
      axi_pkg::region_t                region;
      axi_pkg::atop_t                  atop;
      logic [CVA6Cfg.AxiUserWidth-1:0] user;
    },
    parameter type axi_w_chan_t = struct packed {
      logic [CVA6Cfg.AxiDataWidth-1:0]     data;
      logic [(CVA6Cfg.AxiDataWidth/8)-1:0] strb;
      logic                                last;
      logic [CVA6Cfg.AxiUserWidth-1:0]     user;
    },
    parameter type b_chan_t = struct packed {
      logic [CVA6Cfg.AxiIdWidth-1:0]   id;
      axi_pkg::resp_t                  resp;
      logic [CVA6Cfg.AxiUserWidth-1:0] user;
    },
    parameter type r_chan_t = struct packed {
      logic [CVA6Cfg.AxiIdWidth-1:0]   id;
      logic [CVA6Cfg.AxiDataWidth-1:0] data;
      axi_pkg::resp_t                  resp;
      logic                            last;
      logic [CVA6Cfg.AxiUserWidth-1:0] user;
    },
    parameter type noc_req_t = struct packed {
      axi_aw_chan_t aw;
      logic         aw_valid;
      axi_w_chan_t  w;
      logic         w_valid;
      logic         b_ready;
      axi_ar_chan_t ar;
      logic         ar_valid;
      logic         r_ready;
    },
    parameter type noc_resp_t = struct packed {
      logic    aw_ready;
      logic    ar_ready;
      logic    w_ready;
      logic    b_valid;
      b_chan_t b;
      logic    r_valid;
      r_chan_t r;
    },
    //
    parameter type acc_cfg_t = logic,
    parameter acc_cfg_t AccCfg = '0,
    // CVXIF Types
    parameter type readregflags_t = `READREGFLAGS_T(CVA6Cfg),
    parameter type writeregflags_t = `WRITEREGFLAGS_T(CVA6Cfg),
    parameter type id_t = `ID_T(CVA6Cfg),
    parameter type hartid_t = `HARTID_T(CVA6Cfg),
    parameter type x_compressed_req_t = `X_COMPRESSED_REQ_T(CVA6Cfg, hartid_t),
    parameter type x_compressed_resp_t = `X_COMPRESSED_RESP_T(CVA6Cfg),
    parameter type x_issue_req_t = `X_ISSUE_REQ_T(CVA6Cfg, hartid_t, id_t),
    parameter type x_issue_resp_t = `X_ISSUE_RESP_T(CVA6Cfg, writeregflags_t, readregflags_t),
    parameter type x_register_t = `X_REGISTER_T(CVA6Cfg, hartid_t, id_t, readregflags_t),
    parameter type x_commit_t = `X_COMMIT_T(CVA6Cfg, hartid_t, id_t),
    parameter type x_result_t = `X_RESULT_T(CVA6Cfg, hartid_t, id_t, writeregflags_t),
    parameter type cvxif_req_t =
    `CVXIF_REQ_T(CVA6Cfg, x_compressed_req_t, x_issue_req_t, x_register_t, x_commit_t),
    parameter type cvxif_resp_t =
    `CVXIF_RESP_T(CVA6Cfg, x_compressed_resp_t, x_issue_resp_t, x_result_t),
    // APB types for the HMR configuration slave interface
    parameter type apb_req_t = logic,
    parameter type apb_rsp_t = logic
) (
    // Subsystem Clock - SUBSYSTEM
    input logic clk_i,
    // Asynchronous reset active low - SUBSYSTEM
    input logic rst_ni,
    // Input of DMR checker were not identical
    output logic dmr_failure_o,
    // HMR configuration – APB slave interface (tied off when DMR is disabled)
    input  apb_req_t hmr_apb_req_i,
    output apb_rsp_t hmr_apb_rsp_o,
    // Reset boot address - SUBSYSTEM
    input logic [NumLogicalCores-1:0][CVA6Cfg.VLEN-1:0] boot_addr_i,
    // Hard ID reflected as CSR - SUBSYSTEM
    input logic [NumLogicalCores-1:0][CVA6Cfg.XLEN-1:0] hart_id_i,
    // Level sensitive (async) interrupts - SUBSYSTEM
    input logic [NumLogicalCores-1:0][1:0] irq_i,
    // Inter-processor (async) interrupt - SUBSYSTEM
    input logic [NumLogicalCores-1:0] ipi_i,
    // Timer (async) interrupt - SUBSYSTEM
    input logic [NumLogicalCores-1:0] time_irq_i,
    // Debug (async) request - SUBSYSTEM
    input logic [NumLogicalCores-1:0] debug_req_i,
    // Probes to build RVFI, can be left open when not used - RVFI
    output rvfi_probes_t rvfi_probes_o,
    // CVXIF request - SUBSYSTEM
    output cvxif_req_t cvxif_req_o,
    // CVXIF response - SUBSYSTEM
    input cvxif_resp_t cvxif_resp_i,
    // noc request, can be AXI or OpenPiton - SUBSYSTEM
    output noc_req_t [NumLogicalCores-1:0] noc_req_o,
    // noc response, can be AXI or OpenPiton - SUBSYSTEM
    input noc_resp_t [NumLogicalCores-1:0] noc_resp_i
);

  // Number of D$ request ports (same as in cva6.sv)
  localparam int unsigned NumPorts = 4;

  // HPDcache configuration with external SRAM enabled
  localparam hpdcache_pkg::hpdcache_cfg_t HPDcacheCfg =
      cva6_hpdcache_subsystem_pkg::hpdcacheBuildCfg(CVA6Cfg, NumPorts, 1'b1);

  // External SRAM type definitions
  `HPDCACHE_TYPEDEF_EXT_SRAM_REQ_T(dcache_ext_sram_req_t, HPDcacheCfg);
  `HPDCACHE_TYPEDEF_EXT_SRAM_RESP_T(dcache_ext_sram_resp_t, HPDcacheCfg);

  // RAM types for hpdcache_memwrap
  `HPDCACHE_TYPEDEF_RAM_TYPES_T(sram, HPDcacheCfg);

  typedef logic unsigned [HPDcacheCfg.u.ways-1:0] sram_way_vector_t;
  typedef logic [HPDcacheCfg.tagWidth-1:0] sram_tag_t;
  typedef struct packed {
    logic valid;
    logic wback;
    logic dirty;
    logic fetch;
    sram_tag_t tag;
  } sram_dir_entry_t;

  // I$ SRAM parameters and type definitions
  localparam int unsigned IcacheOffsetWidth = $clog2(CVA6Cfg.ICACHE_LINE_WIDTH / 8);
  localparam int unsigned IcacheClIdxWidth  = CVA6Cfg.ICACHE_INDEX_WIDTH - IcacheOffsetWidth;

  typedef struct packed {
    logic [CVA6Cfg.ICACHE_SET_ASSOC-1:0]                                     tag_req;
    logic                                                                    tag_we;
    logic [IcacheClIdxWidth-1:0]                                             tag_addr;
    logic [CVA6Cfg.ICACHE_SET_ASSOC-1:0][CVA6Cfg.ICACHE_TAG_WIDTH:0]         tag_wdata;
    logic [CVA6Cfg.ICACHE_SET_ASSOC-1:0]                                     data_req;
    logic                                                                    data_we;
    logic [IcacheClIdxWidth-1:0]                                             data_addr;
    logic [CVA6Cfg.ICACHE_LINE_WIDTH-1:0]                                    data_wdata;
    logic [CVA6Cfg.ICACHE_USER_LINE_WIDTH-1:0]                               data_wuser;
  } icache_ext_sram_req_t;

  typedef struct packed {
    logic [CVA6Cfg.ICACHE_SET_ASSOC-1:0][CVA6Cfg.ICACHE_TAG_WIDTH:0]         tag_rdata;
    logic [CVA6Cfg.ICACHE_SET_ASSOC-1:0][CVA6Cfg.ICACHE_LINE_WIDTH-1:0]      data_rdata;
    logic [CVA6Cfg.ICACHE_SET_ASSOC-1:0][CVA6Cfg.ICACHE_USER_LINE_WIDTH-1:0] data_ruser;
  } icache_ext_sram_resp_t;

  // Packed struct wrapping all core scalar inputs
  typedef struct packed {
    logic [CVA6Cfg.VLEN-1:0] boot_addr;
    logic [CVA6Cfg.XLEN-1:0] hart_id;
    logic [1:0]              irq;
    logic                    ipi;
    logic                    time_irq;
    logic                    debug_req;
  } cva6_inputs_t;

  // Register interface types for hmr_unit configuration (PULP reg_intf-compatible)
  typedef struct packed {
    logic [31:0] addr;
    logic        write;
    logic [31:0] wdata;
    logic [ 3:0] wstrb;
    logic        valid;
  } hmr_reg_req_t;
  typedef struct packed {
    logic [31:0] rdata;
    logic        error;
    logic        ready;
  } hmr_reg_rsp_t;

  // Pack top-level inputs into cva6_inputs_t array [NumLogicalCores]
  cva6_inputs_t [NumLogicalCores-1:0] sys_inputs;
  for (genvar i = 0; i < NumLogicalCores; i++) begin : gen_sys_inputs
    assign sys_inputs[i].boot_addr = boot_addr_i[i];
    assign sys_inputs[i].hart_id   = hart_id_i[i];
    assign sys_inputs[i].irq       = irq_i[i];
    assign sys_inputs[i].ipi       = ipi_i[i];
    assign sys_inputs[i].time_irq  = time_irq_i[i];
    assign sys_inputs[i].debug_req = debug_req_i[i];
  end

  // Intermediate signals: cores <-> HMR
  cva6_inputs_t [NumPhysicalCores-1:0] hmr2core;

  noc_req_t  [NumPhysicalCores-1:0] noc_req_core2hmr;
  noc_resp_t [NumPhysicalCores-1:0] noc_resp_hmr2core;

  dcache_ext_sram_req_t  [NumPhysicalCores-1:0] dcache_ext_sram_req_core2hmr;
  dcache_ext_sram_resp_t [NumPhysicalCores-1:0] dcache_ext_sram_resp_hmr2core;

  icache_ext_sram_req_t  [NumPhysicalCores-1:0] icache_ext_sram_req_core2hmr;
  icache_ext_sram_resp_t [NumPhysicalCores-1:0] icache_ext_sram_resp_hmr2core;

  // HMR <-> system signals (dimensioned by NumLogicalCores)
  noc_req_t  [NumLogicalCores-1:0] noc_req_hmr2sys;
  noc_resp_t [NumLogicalCores-1:0] noc_resp_sys2hmr;

  dcache_ext_sram_req_t  dcache_ext_sram_req_hmr2sys;
  dcache_ext_sram_resp_t dcache_ext_sram_resp_sys2hmr;

  icache_ext_sram_req_t  icache_ext_sram_req_hmr2sys;
  icache_ext_sram_resp_t icache_ext_sram_resp_sys2hmr;

  // System NOC binding
  for (genvar i = 0; i < NumLogicalCores; i++) begin : gen_noc_binding
    assign noc_req_o[i]        = noc_req_hmr2sys[i];
    assign noc_resp_sys2hmr[i] = noc_resp_i[i];
  end

  //  External D$ SRAM instantiation (HPDCache only)
  if (CVA6Cfg.DCacheType == config_pkg::HPDCACHE_WT ||
      CVA6Cfg.DCacheType == config_pkg::HPDCACHE_WB ||
      CVA6Cfg.DCacheType == config_pkg::HPDCACHE_WT_WB
  ) begin : gen_dcache_memwrap
    hpdcache_memwrap #(
        .HPDcacheCfg                 (HPDcacheCfg),
        .hpdcache_way_vector_t       (sram_way_vector_t),
        .hpdcache_dir_addr_t         (sram_dir_addr_t),
        .hpdcache_dir_entry_t        (sram_dir_entry_t),
        .hpdcache_data_addr_t        (sram_data_addr_t),
        .hpdcache_data_enable_t      (sram_data_enable_t),
        .hpdcache_data_be_entry_t    (sram_data_be_entry_t),
        .hpdcache_data_entry_t       (sram_data_entry_t),
        .hpdcache_data_row_enable_t  (sram_data_row_enable_t),
        .hpdcache_data_ram_word_sel_t(sram_data_ram_word_sel_t)
    ) i_dcache_memwrap (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),

        // Directory
        .dir_cs_i        (dcache_ext_sram_req_hmr2sys.dir_cs),
        .dir_we_i        (dcache_ext_sram_req_hmr2sys.dir_we),
        .dir_addr_i      (dcache_ext_sram_req_hmr2sys.dir_addr),
        .dir_wentry_i    (dcache_ext_sram_req_hmr2sys.dir_wentry),
        .dir_rentry_o    (dcache_ext_sram_resp_sys2hmr.dir_rentry),
        .dir_err_cor_o   (dcache_ext_sram_resp_sys2hmr.dir_err_cor),
        .dir_err_unc_o   (dcache_ext_sram_resp_sys2hmr.dir_err_unc),
        .dir_err_valid_o (dcache_ext_sram_resp_sys2hmr.dir_err_valid),
        .dir_err_dirty_o (dcache_ext_sram_resp_sys2hmr.dir_err_dirty),

        // Data
        .data_addr_i       (dcache_ext_sram_req_hmr2sys.data_addr),
        .data_cs_i         (dcache_ext_sram_req_hmr2sys.data_cs),
        .data_we_i         (dcache_ext_sram_req_hmr2sys.data_we),
        .data_wbyteenable_i(dcache_ext_sram_req_hmr2sys.data_wbyteenable),
        .data_wentry_i     (dcache_ext_sram_req_hmr2sys.data_wentry),
        .data_rentry_o     (dcache_ext_sram_resp_sys2hmr.data_rentry),
        .data_err_cor_o    (dcache_ext_sram_resp_sys2hmr.data_err_cor),
        .data_err_unc_o    (dcache_ext_sram_resp_sys2hmr.data_err_unc)
    );
  end else begin : gen_no_dcache_memwrap
    assign dcache_ext_sram_resp_sys2hmr = '0;
  end

  //  External I$ SRAM instantiation
  icache_memwrap #(
      .CVA6Cfg                (CVA6Cfg),
      .icache_ext_sram_req_t  (icache_ext_sram_req_t),
      .icache_ext_sram_resp_t (icache_ext_sram_resp_t)
  ) i_icache_memwrap (
      .clk_i  (clk_i),
      .rst_ni (rst_ni),
      .req_i  (icache_ext_sram_req_hmr2sys),
      .resp_o (icache_ext_sram_resp_sys2hmr)
  );

  //  Core instantiation
  //  RVFI and CVXIF are propagated only from core 0 (excluded from HMR)
  rvfi_probes_t [NumPhysicalCores-1:0] rvfi_probes_core;
  cvxif_req_t   [NumPhysicalCores-1:0] cvxif_req_core;
  cvxif_resp_t  [NumPhysicalCores-1:0] cvxif_resp_core;

  assign rvfi_probes_o = rvfi_probes_core[0];
  assign cvxif_req_o   = cvxif_req_core[0];
  // In DMR mode, both cores must see the same CVXIF response to avoid divergence.
  // Core 0's request is forwarded externally; both cores receive the same response.
  for (genvar i = 0; i < NumPhysicalCores; i++) begin : gen_cvxif_resp
    assign cvxif_resp_core[i] = cvxif_resp_i;
  end

  for (genvar i = 0; i < NumPhysicalCores; i++) begin : gen_cva6_core
    cva6 #(
        .CVA6Cfg             (CVA6Cfg),
        .rvfi_probes_instr_t (rvfi_probes_instr_t),
        .rvfi_probes_csr_t   (rvfi_probes_csr_t),
        .rvfi_probes_t       (rvfi_probes_t),
        .exception_t         (exception_t),
        .accelerator_req_t   (accelerator_req_t),
        .accelerator_resp_t  (accelerator_resp_t),
        .acc_mmu_req_t       (acc_mmu_req_t),
        .acc_mmu_resp_t      (acc_mmu_resp_t),
        .axi_ar_chan_t       (axi_ar_chan_t),
        .axi_aw_chan_t       (axi_aw_chan_t),
        .axi_w_chan_t        (axi_w_chan_t),
        .b_chan_t            (b_chan_t),
        .r_chan_t            (r_chan_t),
        .noc_req_t           (noc_req_t),
        .noc_resp_t          (noc_resp_t),
        .acc_cfg_t           (acc_cfg_t),
        .AccCfg              (AccCfg),
        .readregflags_t      (readregflags_t),
        .writeregflags_t     (writeregflags_t),
        .id_t                (id_t),
        .hartid_t            (hartid_t),
        .x_compressed_req_t  (x_compressed_req_t),
        .x_compressed_resp_t (x_compressed_resp_t),
        .x_issue_req_t       (x_issue_req_t),
        .x_issue_resp_t      (x_issue_resp_t),
        .x_register_t        (x_register_t),
        .x_commit_t          (x_commit_t),
        .x_result_t          (x_result_t),
        .cvxif_req_t         (cvxif_req_t),
        .cvxif_resp_t        (cvxif_resp_t),
        .dcache_ext_sram_req_t  (dcache_ext_sram_req_t),
        .dcache_ext_sram_resp_t (dcache_ext_sram_resp_t),
        .IcacheExternalSram     (1'b1),
        .icache_ext_sram_req_t  (icache_ext_sram_req_t),
        .icache_ext_sram_resp_t (icache_ext_sram_resp_t)
    ) i_cva6 (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .boot_addr_i (hmr2core[i].boot_addr),
        .hart_id_i   (hmr2core[i].hart_id),
        .irq_i       (hmr2core[i].irq),
        .ipi_i       (hmr2core[i].ipi),
        .time_irq_i  (hmr2core[i].time_irq),
        .debug_req_i (hmr2core[i].debug_req),
        .rvfi_probes_o        (rvfi_probes_core[i]),
        .cvxif_req_o          (cvxif_req_core[i]),
        .cvxif_resp_i         (cvxif_resp_core[i]),
        .noc_req_o            (noc_req_core2hmr[i]),
        .noc_resp_i           (noc_resp_hmr2core[i]),
        .dcache_ext_sram_req_o  (dcache_ext_sram_req_core2hmr[i]),
        .dcache_ext_sram_resp_i (dcache_ext_sram_resp_hmr2core[i]),
        .icache_ext_sram_req_o  (icache_ext_sram_req_core2hmr[i]),
        .icache_ext_sram_resp_i (icache_ext_sram_resp_hmr2core[i])
    );
  end

  //  HMR / DMR logic
  if (NumPhysicalCores == 1) begin : gen_single_core
    // No DMR – straight passthrough
    assign dmr_failure_o = 1'b0;

    // No HMR unit in single-core: respond to APB with a slave error
    assign hmr_apb_rsp_o.prdata  = '0;
    assign hmr_apb_rsp_o.pready  = 1'b1;
    assign hmr_apb_rsp_o.pslverr = 1'b1;

    always_comb begin
      hmr2core[0]                      = sys_inputs[0];
      noc_req_hmr2sys[0]               = noc_req_core2hmr[0];
      noc_resp_hmr2core[0]             = noc_resp_sys2hmr[0];
      dcache_ext_sram_req_hmr2sys      = dcache_ext_sram_req_core2hmr[0];
      dcache_ext_sram_resp_hmr2core[0] = dcache_ext_sram_resp_sys2hmr;
      icache_ext_sram_req_hmr2sys      = icache_ext_sram_req_core2hmr[0];
      icache_ext_sram_resp_hmr2core[0] = icache_ext_sram_resp_sys2hmr;
    end

  end else if (NumPhysicalCores == 2) begin : gen_hmr

    // Register bus wires between the APB bridge and hmr_unit
    hmr_reg_req_t hmr_reg_req;
    hmr_reg_rsp_t hmr_reg_rsp;

    // Convert the incoming APB slave port to the internal reg bus
    apb_to_reg_v2 #(
      .Feedthrough (1'b0),
      .reg_req_t   (hmr_reg_req_t),
      .reg_rsp_t   (hmr_reg_rsp_t)
    ) i_apb_to_reg (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .penable_i (hmr_apb_req_i.penable),
      .pwrite_i  (hmr_apb_req_i.pwrite),
      .paddr_i   (hmr_apb_req_i.paddr),
      .psel_i    (hmr_apb_req_i.psel),
      .pwdata_i  (hmr_apb_req_i.pwdata),
      .prdata_o  (hmr_apb_rsp_o.prdata),
      .pready_o  (hmr_apb_rsp_o.pready),
      .pslverr_o (hmr_apb_rsp_o.pslverr),
      .reg_req_o (hmr_reg_req),
      .reg_rsp_i (hmr_reg_rsp)
    );

    // Raw core inputs from HMR unit (boot_addr overridden below via checkpoint mechanism)
    cva6_inputs_t [1:0] hmr_core_inputs_raw;
    // Per-core boot address from HMR checkpoint mechanism
    logic [1:0][CVA6Cfg.VLEN-1:0] hmr_core_bootaddress;
    // Per-core setback signal (rapid recovery, unused in fixed lockstep stub)
    logic [1:0] hmr_core_setback;

    hmr_unit #(
      // Fixed DMR lockstep: 2 physical cores, 1 logical core visible to the system.
      // TMR and rapid recovery are disabled. The NOC request is the voted nominal output.
      .NumCores              (2),
      .DMRFixed              (1'b1),
      .DMRSupported          (1'b0),
      .TMRFixed              (1'b0),
      .TMRSupported          (1'b0),
      .InterleaveGrps        (1'b1),
      .all_inputs_t          (cva6_inputs_t),
      .nominal_outputs_t     (noc_req_t),
      .DefaultNominalOutputs ('0),
      .SeparateData          (1'b0),
      .NumBusVoters          (1),
      .bus_outputs_t         (logic),
      .DefaultBusOutputs     ('0),
      .reg_req_t             (hmr_reg_req_t),
      .reg_rsp_t             (hmr_reg_rsp_t),
      .RapidRecovery         (1'b0),
      .SysDataWidth          (CVA6Cfg.VLEN)
    ) i_hmr_unit (
      .clk_i  (clk_i),
      .rst_ni (rst_ni),

      // Register interface: driven by the APB-to-reg bridge
      .reg_request_i         (hmr_reg_req),
      .reg_response_o        (hmr_reg_rsp),

      // TMR signals: unused (DMRFixed, TMRSupported=0)
      .tmr_failure_o         (/* open */),
      .tmr_error_o           (/* open */),
      .tmr_resynch_req_o     (/* open */),
      .tmr_sw_synch_req_o    (/* open */),
      .tmr_cores_synch_i     ('1),

      // DMR signals
      .dmr_failure_o         (dmr_failure_o),
      .dmr_resynch_req_o     (/* open */),
      .dmr_sw_synch_req_o    (/* open */),
      .dmr_cores_synch_i     ('1),
      .redundancy_enable_o   (/* open */),

      // Rapid recovery: disabled
      .rapid_recovery_o      (/* open */),
      .core_backup_i         ('0),

      // Boot address for checkpoint mechanism (NumSysCores=1 in DMRFixed)
      .sys_bootaddress_i     (boot_addr_i[0]),

      // System side (NumSysCores=1 for DMRFixed)
      .sys_inputs_i          (sys_inputs),
      .sys_nominal_outputs_o (noc_req_hmr2sys),
      .sys_bus_outputs_o     (/* open, SeparateData=0 */),
      .sys_fetch_en_i        ('1),
      .enable_bus_vote_i     ('1),

      // Core side (NumCores=2)
      .core_bootaddress_o    (hmr_core_bootaddress),
      .core_setback_o        (hmr_core_setback),
      .core_inputs_o         (hmr_core_inputs_raw),
      .core_nominal_outputs_i(noc_req_core2hmr),
      .core_bus_outputs_i    ('0)
    );

    // Assemble final core inputs: override boot_addr with the checkpoint-aware value from HMR
    for (genvar i = 0; i < 2; i++) begin : gen_hmr_core_inputs
      always_comb begin
        hmr2core[i]           = hmr_core_inputs_raw[i];
        hmr2core[i].boot_addr = hmr_core_bootaddress[i];
      end
    end

    // NOC response: broadcast the single system response to both cores in lockstep
    for (genvar i = 0; i < 2; i++) begin : gen_noc_resp_bcast
      assign noc_resp_hmr2core[i] = noc_resp_sys2hmr[0];
    end

    // Cache SRAM: both cores produce identical requests in lockstep.
    // Forward core[0]'s requests to the shared SRAMs and broadcast the response.
    assign dcache_ext_sram_req_hmr2sys = dcache_ext_sram_req_core2hmr[0];
    assign icache_ext_sram_req_hmr2sys = icache_ext_sram_req_core2hmr[0];
    for (genvar i = 0; i < 2; i++) begin : gen_sram_resp_bcast
      assign dcache_ext_sram_resp_hmr2core[i] = dcache_ext_sram_resp_sys2hmr;
      assign icache_ext_sram_resp_hmr2core[i] = icache_ext_sram_resp_sys2hmr;
    end

  end else begin
    $error("Unsupported number of cores.");
  end

endmodule : cva6_dcls
