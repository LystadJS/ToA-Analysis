plot_country <- function(series, context, name, path) {
  grDevices::pdf(path,width=10,height=10,useDingbats=FALSE)
  on.exit(dev.off())
  layout(matrix(c(1,2,3,4,5,5),3,2,byrow=TRUE))
  par(mar=c(4,4.6,2.6,1),oma=c(2.4,0,3,0),las=1)
  blank <- function(title) {
    plot.new()
    title(main=title,cex.main=0.93)
    text(.5,.5,"No observation in these releases",col="grey40")
  }
  labels <- c("U.S. economic assistance obligations","U.S. all-sector disbursements","PRC adjusted official commitments","PRC CLG face-value commitments")
  for (i in seq_along(labels)) {
    d <- series[series==labels[i] & !is.na(value)][order(year)]
    if (!nrow(d)) { blank(labels[i]); next }
    plot(d$year,d$value/1e6,pch=16,col=c("#205889","#307663","#9D4736","#86538F")[i],
         xlab=if (i>=3) "Calendar year" else "Fiscal year",ylab="Current USD, millions",
         main=labels[i],cex.main=.93,cex=.7)
    abline(h=0,col="grey75",lty=3)
  }
  if (nrow(context)) {
    plot(days~year,data=context,type="n",xlab="Survey year",ylab="Median days",
         main="National logistics lead time",cex.main=.93)
    points(days~year,data=context[source_id=="import"],pch=16,col="#205889")
    points(days~year,data=context[source_id=="export"],pch=4,col="#9D4736")
    legend("topright",legend=c("Import","Export"),pch=c(16,4),col=c("#205889","#9D4736"),bty="n",cex=.8)
  } else blank("National logistics lead time")
  mtext(name,outer=TRUE,side=3,font=2,cex=1.2)
  mtext("Each panel uses its own scale. Points show available years. Finance panels sum disclosed amounts only.",
        outer=TRUE,side=1,cex=.8)
}
