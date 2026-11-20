source("R/fonts.R")
Sys.setenv(FONTCONFIG_FILE=normalizePath("assets/fonts/fonts.conf"))
library(ggplot2)

toa_theme <- function(size=11) {
  theme_minimal(base_size=size,base_family=toa_fonts[["body"]]) +
    theme(plot.title=element_text(family=toa_fonts[["title"]],face="bold",size=rel(1.55),colour="#203339"),
          plot.subtitle=element_text(colour="#45565a",margin=margin(b=8)),
          plot.title.position="plot", plot.caption.position="plot",
          plot.caption=element_text(hjust=0,colour="#536165",size=rel(.81),margin=margin(t=8)),
          axis.text=element_text(colour="#3c484b"),
          axis.text.x=element_text(family=toa_fonts[["number"]],size=rel(.82)),
          axis.text.y=element_text(family=toa_fonts[["number"]],size=rel(.82)),
          axis.title=element_text(size=rel(.9)),
          panel.grid.major=element_line(colour="#dedede",linewidth=.35),
          panel.grid.minor=element_line(colour="#f0f0f0",linewidth=.22),
          legend.position="bottom",legend.title=element_blank(),
          plot.background=element_rect(fill="white",colour=NA))
}
