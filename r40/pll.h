/* RX and TX synthesizers. */
#ifndef PLL_H
#define PLL_H

#define PLL_RX 0
#define PLL_TX 1
#define PLL_STEP 6250L		/* Hz per VCO channel */
#define RX_IF 45000000L		/* RX VCO = f + 45 MHz */

void pll_init(void);
void pll_vco(int which, unsigned long hz);

#endif
