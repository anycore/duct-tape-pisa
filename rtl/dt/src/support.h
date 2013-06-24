#ifndef __SUPPORT_H__
#define __SUPPORT_H__

#include <stdint.h>
#include <inttypes.h>

typedef char BOOL;
#define TRUE 1
#define FALSE 0

typedef enum {
    ENTRY_INCOMPLETE = 1,
    ENTRY_COMPLETE = 2
} status_t;

typedef enum {
    ENTRY_DEFINITION,
    ENTRY_PHI_NODE, /* the reconvergence point after an if or if-else or the continuation point after a loop */
    ENTRY_INSTRUCTION,
    ENTRY_IDATA,
    ENTRY_FDATA
} type_t;

typedef struct {
    uint32_t opcode;
    union {
        uint32_t rdst;
        uint32_t rsrc0;
    };
    union {
        uint32_t rsrc1;
        uint32_t rbase;
    };
    union {
        uint32_t rsrc2;
    };
    union {
        int32_t imm;
        int32_t shamt;
        uint32_t target_address;
    };
    union {
        char *target_name;
    };
} instruction_t;

typedef struct mem_entry_type {
    status_t status;
    type_t type;
    char * name;
    uint32_t address;
    uint32_t size; /* in bytes -- could be zero for definitions */

    instruction_t * inst;

    /* value */
    union {
        uint64_t encoding;
        uint64_t ivalue;
        float    fvalue;
        double   dvalue;
    };

    struct mem_entry_type * next;
} mem_entry_t;

mem_entry_t * new_mem_entry(type_t, uint32_t);
mem_entry_t * new_instruction(uint32_t);
mem_entry_t * append_inst(mem_entry_t*, mem_entry_t*);
char *internal_name();

typedef struct memblock_list_type {
    uint32_t min_address;
    uint32_t max_address;
    mem_entry_t *head;
    struct memblock_list_type * next;
} memblock_list_t;

void add_memblock(mem_entry_t*);
void check_mem_bounds();
void check_scratchpad();
void calculate_offsets();
uint64_t encode_instruction(instruction_t *);
void encode_instructions();
void print_instructions();

void write_flat(char *);
void write_fpga(char *, char *, char *);
void write_scratchpads(char *, char *);

typedef enum {
    SYMTAB_IREG,
    SYMTAB_FREG,
    SYMTAB_TREG,
    SYMTAB_MEM
} symtab_type_t;

typedef struct symtab_entry_type {
    char * name;
    symtab_type_t type;
    uint32_t value; /* either address or reg no */
    struct symtab_entry_type * next;
} symtab_entry_t;

void symtab_new(char*, symtab_type_t);
void symtab_update(char*, uint32_t);
int symtab_lookup(char*);
symtab_type_t symtab_type(char*);
void dump_symtab();


void set_pc(uint32_t);

/* PISA Special Regs */
#define PISA_HI            32
#define PISA_LO            33

/* PISA Opcodes */
#define PISA_J             0x01
#define PISA_JAL           0x02
#define PISA_JR            0x03
#define PISA_JALR          0x04
#define PISA_BEQ           0x05
#define PISA_BNE           0x06
#define PISA_BLEZ          0x07
#define PISA_BGTZ          0x08
#define PISA_BLTZ          0x09
#define PISA_BGEZ          0x0a
#define PISA_BC1F          0x0b
#define PISA_BC1T          0x0c

#define PISA_LB_D          0x20
#define PISA_LB_I          0xc0
#define PISA_LBU_D         0x22
#define PISA_LBU_I         0xc1
#define PISA_LH_D          0x24
#define PISA_LH_I          0xc2
#define PISA_LHU_D         0x26
#define PISA_LHU_I         0xc3
#define PISA_LW_D          0x28
#define PISA_LW_I          0xc4
#define PISA_DLW_D         0x29
#define PISA_DLW_I         0xce
#define PISA_L_S_D         0x2a
#define PISA_L_S_I         0xc5
#define PISA_L_D_D         0x2b
#define PISA_L_D_I         0xcf
#define PISA_LWL           0x2c
#define PISA_LWR           0x2d
#define PISA_SB_D          0x30
#define PISA_SB_I          0xc6
#define PISA_SH_D          0x32
#define PISA_SH_I          0xc7
#define PISA_SW_D          0x34
#define PISA_SW_I          0xc8
#define PISA_DSW_D         0x35
#define PISA_DSW_I         0xd0
#define PISA_DSZ_D         0x38
#define PISA_DSZ_I         0xd1
#define PISA_S_S_D         0x36
#define PISA_S_S_I         0xc9
#define PISA_S_D_D         0x37
#define PISA_S_D_I         0xd2
#define PISA_SWL           0x39
#define PISA_SWR           0x3a

#define PISA_ADD           0x40
#define PISA_ADDI          0x41
#define PISA_ADDU          0x42
#define PISA_ADDIU         0x43
#define PISA_SUB           0x44
#define PISA_SUBU          0x45
#define PISA_MULT          0x46
#define PISA_MULTU         0x47
#define PISA_DIV           0x48
#define PISA_DIVU          0x49
#define PISA_MFHI          0x4a
#define PISA_MTHI          0x4b
#define PISA_MFLO          0x4c
#define PISA_MTLO          0x4d
#define PISA_AND           0x4e
#define PISA_ANDI          0x4f
#define PISA_OR            0x50
#define PISA_ORI           0x51
#define PISA_XOR           0x52
#define PISA_XORI          0x53
#define PISA_NOR           0x54
#define PISA_SLL           0x55
#define PISA_SLLV          0x56
#define PISA_SRL           0x57
#define PISA_SRLV          0x58
#define PISA_SRA           0x59
#define PISA_SRAV          0x5a
#define PISA_SLT           0x5b
#define PISA_SLTI          0x5c
#define PISA_SLTU          0x5d
#define PISA_SLTIU         0x5e  /* CHECK THIS ONE */

#define PISA_ADD_S         0x70
#define PISA_ADD_D         0x71
#define PISA_SUB_S         0x72
#define PISA_SUB_D         0x73
#define PISA_MUL_S         0x74
#define PISA_MUL_D         0x75
#define PISA_DIV_S         0x76
#define PISA_DIV_D         0x77
#define PISA_ABS_S         0x78
#define PISA_ABS_D         0x79
#define PISA_MOV_S         0x7a
#define PISA_MOV_D         0x7b
#define PISA_NEG_S         0x7c
#define PISA_NEG_D         0x7d
#define PISA_CVT_S_D       0x80
#define PISA_CVT_S_W       0x81
#define PISA_CVT_D_S       0x82
#define PISA_CVT_D_W       0x83
#define PISA_CVT_W_S       0x84
#define PISA_CVT_W_D       0x85
#define PISA_C_EQ_S        0x90
#define PISA_C_EQ_D        0x91
#define PISA_C_LT_S        0x92
#define PISA_C_LT_D        0x93
#define PISA_C_LE_S        0x94
#define PISA_C_LE_D        0x95
#define PISA_SQRT_S        0x96
#define PISA_SQRT_D        0x97

#define PISA_NOP           0x00
#define PISA_SYSCALL       0xa0
#define PISA_BREAK         0xa1
#define PISA_LUI           0xa2
#define PISA_MFC1          0xa3
#define PISA_MTC1          0xa5

#define PISA_M1T_TRF       0xf3
#define PISA_M2T_TRF       0xf2
#define PISA_MF_TRF        0xf1
#define PISA_BARRIER       0xf0
#define PISA_ERET          0xef
#define PISA_MIGRATE       0xed

#endif
