10 REM Test byte variables with & suffix
20 LET A& = 100
30 PRINT A&
40 LET B& = 255
50 PRINT B&
60 LET C& = 0
70 PRINT C&
80 REM Test overflow (should clamp to 255)
90 LET D& = 300
100 PRINT D&
110 REM Test underflow (should clamp to 0)
120 LET E& = -50
130 PRINT E&
140 REM Test with expressions
150 LET F& = 100 + 200
160 PRINT F&
170 REM Test with float conversion
180 LET G& = 127.8
190 PRINT G&
200 REM Test byte array
210 DIM BYTES&(3)
220 LET BYTES&(0) = 10
230 LET BYTES&(1) = 128
240 LET BYTES&(2) = 300
250 LET BYTES&(3) = -10
260 PRINT BYTES&(0)
270 PRINT BYTES&(1)
280 PRINT BYTES&(2)
290 PRINT BYTES&(3)
300 REM Test undefined byte variable defaults to 0
310 PRINT UNDEF&
320 END
