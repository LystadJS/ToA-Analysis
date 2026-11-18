# Quantify changes for three related registration procedures measured by the same project.
source("R/common.R")
us <- connect("toa_us")
x <- as.data.table(dbGetQuery(us,"
  SELECT r.id,r.indicator,r.baseline,r.actual,r.target,r.unit,p.locator,s.download_url
  FROM toa.result r JOIN toa.program p ON p.id=r.program_id JOIN toa.source s USING(source_id)
  WHERE r.id IN ('itt-73858','itt-73859','itt-73860') ORDER BY r.id DESC"))
dbDisconnect(us)
stopifnot(nrow(x)==3L,all(x$unit=="Minutes"),all(x$baseline>0))
x[, `:=`(change_minutes=actual-baseline, percent_change=round(100*(actual/baseline-1),1))]
dir.create("artifacts",showWarnings=FALSE)
fwrite(x,"artifacts/philippines_registration.csv")
pdf("artifacts/philippines_registration.pdf",width=9,height=4.7,useDingbats=FALSE)
par(mar=c(4.4,10,3.5,2),las=1)
y <- 3:1
plot.new()
plot.window(xlim=c(0,62),ylim=c(.4,3.65))
axis(1,at=seq(0,60,10))
axis(2,at=y,labels=c("Manual books","Loose-leaf books","Authority to print"),tick=FALSE)
segments(x$baseline,y,x$actual,y,lwd=2,col="grey65")
points(x$baseline,y,pch=1,cex=1.3)
points(x$actual,y,pch=16,cex=1.3,col="#205889")
text(x$baseline,y+.17,format(x$baseline,trim=TRUE),cex=.8)
text(x$actual,y-.17,format(x$actual,trim=TRUE),cex=.8,col="#205889")
legend("topright",c("Baseline","Reported actual"),pch=c(1,16),col=c("black","#205889"),bty="n",horiz=TRUE,cex=.8)
title(main="Registration processing time in the Philippines",xlab="Minutes per secondary registration application")
mtext("MCC Revenue Administration Reform Project | Monitoring indicators 73858-73860",side=1,line=3.2,cex=.8)
invisible(dev.off())
