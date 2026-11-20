source("R/plot_theme.R")

plot_country <- function(series, context, name, path) {
  grDevices::cairo_pdf(path,width=10.8,height=10)
  on.exit(grDevices::dev.off())
  blank <- function(title) {
    ggplot() + annotate("text",x=0,y=0,label="No observation in these releases",
                        family=toa_fonts[["body"]],colour="#536165",size=3.4) +
      scale_x_continuous(breaks=NULL) + scale_y_continuous(breaks=NULL) +
      labs(title=title,x=NULL,y=NULL) + toa_theme()
  }
  labels <- c("U.S. economic assistance obligations","U.S. all-sector disbursements",
              "PRC adjusted official commitments","PRC CLG face-value commitments")
  colours <- c("#2a7771","#2a7771","#a55732","#a55732")
  panels <- lapply(seq_along(labels),function(i) {
    d <- series[series==labels[i] & !is.na(value)][order(year)]
    if (!nrow(d)) return(blank(labels[i]))
    ggplot(d,aes(year,value/1e6)) +
      geom_hline(yintercept=0,colour="#c4cacc",linewidth=.35) +
      geom_point(colour=colours[i],size=1.75) +
      scale_x_continuous(breaks=function(limits) { ticks <- pretty(limits,5); ticks[ticks==round(ticks)] },labels=scales::label_number(accuracy=1,big.mark="")) +
      labs(title=labels[i], x=if(i>=3) "Calendar year" else "Fiscal year",y="Current USD, millions") +
      toa_theme()
  })
  logistics <- blank("National logistics lead time")
  if (nrow(context)) {
    logistics <- ggplot(context,aes(year,days,colour=source_id,shape=source_id)) +
      geom_point(size=2.5) +
      scale_colour_manual(values=c(import="#2a7771",export="#a55732"),breaks=c("import","export"),labels=c("Import","Export")) +
      scale_shape_manual(values=c(import=16,export=4),breaks=c("import","export"),labels=c("Import","Export")) +
      scale_x_continuous(breaks=sort(unique(context$year))) +
      labs(title="National logistics lead time",x="Survey year",y="Median days") + toa_theme()
  }
  panels[[5]] <- logistics
  page <- patchwork::wrap_plots(panels,design="AB\nCD\nEE") +
    patchwork::plot_annotation(title=name,
      caption="Each panel uses its own scale. Points show observed years. Finance panels sum disclosed amounts only.",
      theme=toa_theme(14) + theme(plot.caption=element_text(family=toa_fonts[["number"]],size=8)))
  print(page)
}
