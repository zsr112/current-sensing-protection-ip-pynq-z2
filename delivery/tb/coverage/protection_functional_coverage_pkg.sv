package protection_functional_coverage_pkg;
  // FCG-01 observed fault origin.  The classifier contract has a single
  // overcurrent code, so channel attribution is observed at the comparator
  // inputs rather than invented as a new RTL fault code.
  localparam logic [3:0] FC_FT_NONE           = 4'd0;
  localparam logic [3:0] FC_FT_CH1_OC         = 4'd1;
  localparam logic [3:0] FC_FT_CH2_OC         = 4'd2;
  localparam logic [3:0] FC_FT_DUAL_OC        = 4'd3;
  localparam logic [3:0] FC_FT_MISMATCH       = 4'd4;
  localparam logic [3:0] FC_FT_SENSOR_OPEN    = 4'd5;
  localparam logic [3:0] FC_FT_SENSOR_SAT     = 4'd6;
  localparam logic [3:0] FC_FT_SENSOR_STUCK   = 4'd7;
  localparam logic [3:0] FC_FT_OC_WITH_SENSOR = 4'd8;

  localparam logic [1:0] FC_REL_BELOW = 2'd0;
  localparam logic [1:0] FC_REL_EQUAL = 2'd1;
  localparam logic [1:0] FC_REL_ABOVE = 2'd2;

  // FCG-05 clear/recovery outcomes.  These event values are asserted by the
  // harness only after checking the corresponding DUT observation.
  localparam logic [2:0] FC_CLEAR_LIVE_REJECTED    = 3'd0;
  localparam logic [2:0] FC_CLEAR_NO_CLEAR_RETAINED = 3'd1;
  localparam logic [2:0] FC_CLEAR_LEGAL             = 3'd2;
  localparam logic [2:0] FC_CLEAR_REPEATED          = 3'd3;
  localparam logic [2:0] FC_CLEAR_RECOVERY_COMPLETE = 3'd4;

  // FCG-07 first-fault retention observations.
  localparam logic [1:0] FC_RET_FIRST_CAPTURED     = 2'd0;
  localparam logic [1:0] FC_RET_LATER_NOT_OVERWRITE = 2'd1;
  localparam logic [1:0] FC_RET_NEW_AFTER_RECOVERY  = 2'd2;

  // FCG-08 sample-valid modes and registered health status classes.
  localparam logic [1:0] FC_SAMPLE_INVALID    = 2'd0;
  localparam logic [1:0] FC_SAMPLE_AFTER_GAP  = 2'd1;
  localparam logic [1:0] FC_SAMPLE_CONTINUOUS = 2'd2;
  localparam logic [1:0] FC_SAMPLE_GAP_START  = 2'd3;

  localparam logic [2:0] FC_HEALTH_STATUS_NONE     = 3'd0;
  localparam logic [2:0] FC_HEALTH_STATUS_OPEN     = 3'd1;
  localparam logic [2:0] FC_HEALTH_STATUS_SAT      = 3'd2;
  localparam logic [2:0] FC_HEALTH_STATUS_STUCK    = 3'd3;
  localparam logic [2:0] FC_HEALTH_STATUS_MULTIPLE = 3'd4;

  // FCG-09 operation values preserve the current register/AXI contract.
  localparam logic [3:0] FC_REG_CTRL_DISABLED = 4'd0;
  localparam logic [3:0] FC_REG_CLEAR_ONLY     = 4'd1;
  localparam logic [3:0] FC_REG_ENABLE         = 4'd2;
  localparam logic [3:0] FC_REG_TH_OC1         = 4'd3;
  localparam logic [3:0] FC_REG_TH_OC2         = 4'd4;
  localparam logic [3:0] FC_REG_TH_DIFF        = 4'd5;
  localparam logic [3:0] FC_REG_PWM_PERIOD     = 4'd6;
  localparam logic [3:0] FC_REG_PWM_DUTY       = 4'd7;
  localparam logic [3:0] FC_REG_STATUS_READ    = 4'd8;
  localparam logic [3:0] FC_REG_FAULT_READ     = 4'd9;
  localparam logic [3:0] FC_REG_UNKNOWN        = 4'd10;
  localparam logic [3:0] FC_REG_WSTRB          = 4'd11;

  localparam logic [2:0] FC_REG_CLASS_CONTROL   = 3'd0;
  localparam logic [2:0] FC_REG_CLASS_THRESHOLD = 3'd1;
  localparam logic [2:0] FC_REG_CLASS_PWM_CONFIG = 3'd2;
  localparam logic [2:0] FC_REG_CLASS_STATUS    = 3'd3;
  localparam logic [2:0] FC_REG_CLASS_FAULT     = 3'd4;
  localparam logic [2:0] FC_REG_CLASS_UNKNOWN   = 3'd5;
  localparam logic [2:0] FC_REG_CLASS_STROBE    = 3'd6;

  localparam logic [1:0] FC_REG_EFFECT_APPLIED   = 2'd0;
  localparam logic [1:0] FC_REG_EFFECT_OBSERVED  = 2'd1;
  localparam logic [1:0] FC_REG_EFFECT_NO_EFFECT = 2'd2;
endpackage
