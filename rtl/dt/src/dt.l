  /*
   * dt.l lexer
   */

%option noyywrap case-insensitive yylineno

%{
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include "support.h"
#include "dt.tab.h"
%}

%%

  /* Instruction Opcodes */
j                                {return OP_J;}
jal                              {return OP_JAL;}
jr                               {return OP_JR;}
jalr                             {return OP_JALR;}
beq                              {return OP_BEQ;}
bne                              {return OP_BNE;}
blez                             {return OP_BLEZ;}
bgtz                             {return OP_BGTZ;}
bltz                             {return OP_BLTZ;}
bgez                             {return OP_BGEZ;}
bc1f                             {return OP_BCF;}
bc1t                             {return OP_BCT;}

lb                               {return OP_LB;}
lbu                              {return OP_LBU;}
lh                               {return OP_LH;}
lhu                              {return OP_LHU;}
lw                               {return OP_LW;}
dlw                              {return OP_DLW;}
l\.s                             {return OP_L_S;}
l\.d                             {return OP_L_D;}
lwl                              {return OP_LWL;}
lwr                              {return OP_LWR;}
sb                               {return OP_SB;}
sh                               {return OP_SH;}
sw                               {return OP_SW;}
dsw                              {return OP_DSW;}
dsz                              {return OP_DSZ;}
s\.s                             {return OP_S_S;}
s\.d                             {return OP_S_D;}
swl                              {return OP_SWL;}
swr                              {return OP_SWR;}

add                              {return OP_ADD;}
addi                             {return OP_ADDI;}
addu                             {return OP_ADDU;}
addiu                            {return OP_ADDIU;}
sub                              {return OP_SUB;}
subu                             {return OP_SUBU;}
mult                             {return OP_MULT;}
multu                            {return OP_MULTU;}
div                              {return OP_DIV;}
divu                             {return OP_DIVU;}
mfhi                             {return OP_MFHI;}
mthi                             {return OP_MTHI;}
mflo                             {return OP_MFLO;}
mtlo                             {return OP_MTLO;}
and                              {return OP_AND;}
andi                             {return OP_ANDI;}
or                               {return OP_OR;}
ori                              {return OP_ORI;}
xor                              {return OP_XOR;}
xori                             {return OP_XORI;}
nor                              {return OP_NOR;}
sll                              {return OP_SLL;}
sllv                             {return OP_SLLV;}
srl                              {return OP_SRL;}
srlv                             {return OP_SRLV;}
sra                              {return OP_SRA;}
srav                             {return OP_SRAV;}
slt                              {return OP_SLT;}
slti                             {return OP_SLTI;}
sltu                             {return OP_SLTU;}
sltiu                            {return OP_SLTIU;}

add\.s                           {return OP_ADD_S;}
add\.d                           {return OP_ADD_D;}
sub\.s                           {return OP_SUB_S;}
sub\.d                           {return OP_SUB_D;}
mul\.s                           {return OP_MUL_S;}
mul\.d                           {return OP_MUL_D;}
div\.s                           {return OP_DIV_S;}
div\.d                           {return OP_DIV_D;}
abs\.s                           {return OP_ABS_S;}
abs\.d                           {return OP_ABS_D;}
mov\.s                           {return OP_MOV_S;}
mov\.d                           {return OP_MOV_D;}
neg\.s                           {return OP_NEG_S;}
neg\.d                           {return OP_NEG_D;}
cvt\.s\.d                        {return OP_CVT_S_D;}
cvt\.s\.w                        {return OP_CVT_S_W;}
cvt\.d\.s                        {return OP_CVT_D_S;}
cvt\.d\.w                        {return OP_CVT_D_W;}
cvt\.w\.s                        {return OP_CVT_W_S;}
cvt\.w\.d                        {return OP_CVT_W_D;}
c\.eq\.s                         {return OP_C_EQ_S;}
c\.eq\.d                         {return OP_C_EQ_D;}
c\.lt\.s                         {return OP_C_LT_S;}
c\.lt\.d                         {return OP_C_LT_D;}
c\.le\.s                         {return OP_C_LE_S;}
c\.le\.d                         {return OP_C_LE_D;}
sqrt\.s                          {return OP_SQRT_S;}
sqrt\.d                          {return OP_SQRT_D;}

nop                              {return OP_NOP;}
syscall                          {return OP_SYSCALL;}
break                            {return OP_BREAK;}
lui                              {return OP_LUI;}
mfc1                             {return OP_MFC;}
mtc1                             {return OP_MTC;}
return                           {return OP_RET;}

m1t_trf                          {return OP_M1T_TRF;}
m2t_trf                          {return OP_M2T_TRF;}
mf_trf                           {return OP_MF_TRF;}
barrier                          {return OP_BARRIER;}
trf_barrier                      {return OP_BARRIER;}
eret                             {return OP_ERET;}
migrate                          {return OP_MIGRATE;}


  /* Operators */
\+                               {return PLUS;}
-                                {return MINUS;}
\*                               {return MULTIPLY;}
\/                               {return DIVIDE;}
&                                {return AND;}
\|                               {return OR;}
~                                {return NOT;}
\^                               {return XOR;}
\<\<                             {return LSHIFT;}
\>\>                             {return RSHIFT;}
@                                {return ADDRESSOF;}
\<                               {return LT;}
\>                               {return GT;}
\<=                              {return LTE;}
\>=                              {return GTE;}
==                               {return EQ;}
!=                               {return NEQ;}
=                                {return ASSIGN;}


  /* Registers */
$r[0-9]+[ \t]*                   {yylval.ivalue = (int64_t) atoi(&yytext[2]); return IREG;}
$f[0-9]+[ \t]*                   {yylval.ivalue = (int64_t) atoi(&yytext[2]); return FREG;}
$t[0-9]+[ \t]*                   {yylval.ivalue = (int64_t) atoi(&yytext[2]); return TREG;}
$hi[ \t]*                        {return HIREG;}
$lo[ \t]*                        {return LOREG;}
$pc[ \t]*                        {return PCREG;}

  /* Code Blocks */
mem                              {return MEMBLOCK;}
if                               {return IFBLOCK;}
else                             {return ELSEBLOCK;}
while                            {return WHILEBLOCK;}
do                               {return DOBLOCK;}
until                            {return UNTILBLOCK;}

  /* Immediates / Offsets */
#[-+]?[0-9]+                     {yylval.ivalue = (int64_t) atoi(&yytext[1]); return IIMM;}
0x[0-9a-f]+                      {sscanf(yytext,"%x",&(yylval.ivalue)); return IIMM;}
#[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)? {yylval.fvalue = atof(&yytext[1]); return FIMM;}


  /* Comments */
%.*                              /* gobble up comments */

  /* Labels / Names */
[a-z][a-z0-9_]*                  {yylval.string = strdup(yytext);return LABEL;}

  /* Misc */
\[                               {return LBRACKET;}
\]                               {return RBRACKET;}
\{                               {return LBRACE;}
\}                               {return RBRACE;}
\(                               {return LPAREN;}
\)                               {return RPAREN;}
:                                {return COLON;}
!                                {return BANG;}
[ \t]+                           /* whitespace -- do nothing */
[\n\r]+                          /* linefeed -- do nothing */
,                                /* commas -- ignore them too */
.                                {return UNKNOWN;}

%%

