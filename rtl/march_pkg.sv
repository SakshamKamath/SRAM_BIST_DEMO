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
    ERR_ABORT
  } seq_e;
endpackage
