/* stdarg for the lcc H8/500 back end: arguments are pushed as 2-byte
   aligned words (char and short promoted to int), right to left */
#ifndef _STDARG_H
#define _STDARG_H
typedef char *va_list;
#define __va_size(t) ((sizeof(t) + 1) / 2 * 2)
#define va_start(ap, last) ((ap) = (char *)&(last) + __va_size(last))
/* a char-sized argument is the low (second) byte of its word */
#define va_arg(ap, t) (*(t *)(((ap) += __va_size(t)) - (sizeof(t) == 1 ? 1 : __va_size(t))))
#define va_end(ap) ((void)0)
#endif
