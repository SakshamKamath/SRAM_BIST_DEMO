package march_pkg;
  typedef enum logic [3:0] {
    IDLE,
    STAGE_0,
    STAGE_1,
    STAGE_2,
    STAGE_3,
    STAGE_4,
    STAGE_5,
    DONE,
    REPAIR_WAIT
  } seq_e;
endpackage

