# Quantify changes for three related registration procedures measured by the same project.
source("R/common.R")
us <- connect("toa_us")
x <- as.data.table(dbGetQuery(us,"
  SELECT r.id,r.indicator,r.baseline,r.actual,r.target,r.unit,r.period_start,r.period_end,p.locator,s.download_url
  FROM toa.result r JOIN toa.program p ON p.id=r.program_id JOIN toa.source s USING(source_id)
  WHERE r.id IN ('itt-73858-ActualQ20','itt-73859-ActualQ20','itt-73860-ActualQ20') ORDER BY r.id DESC"))
dbDisconnect(us)
stopifnot(nrow(x)==3L,all(x$unit=="Minutes"),all(x$baseline>0))
x[, `:=`(change_minutes=actual-baseline, percent_change=round(100*(actual/baseline-1),1))]
dir.create("artifacts",showWarnings=FALSE)
fwrite(x,"artifacts/philippines_registration.csv")
source("R/plot_theme.R")
x[, procedure:=factor(c("Manual books","Loose-leaf books","Authority to print"),
                      levels=c("Authority to print","Loose-leaf books","Manual books"))]
points <- melt(x,id.vars="procedure",measure.vars=c("baseline","actual"),variable.name="observation",value.name="minutes")
chart <- ggplot(x,aes(y=procedure)) +
  geom_segment(aes(x=baseline,xend=actual,yend=procedure),colour="#acb7b6",linewidth=.9) +
  geom_point(data=points,aes(x=minutes,shape=observation,colour=observation),size=3.2,stroke=1.1) +
  geom_text(data=points,aes(x=minutes,label=minutes,vjust=ifelse(observation=="baseline",-1,1.8)),
            family=toa_fonts[["number"]],size=3) +
  scale_shape_manual(values=c(baseline=1,actual=16),labels=c("Baseline","Reported actual")) +
  scale_colour_manual(values=c(baseline="#506367",actual="#23766f"),labels=c("Baseline","Reported actual")) +
  scale_x_continuous(limits=c(0,60),breaks=seq(0,60,10)) +
  labs(title="Registration processing time in the Philippines",x="Minutes per secondary registration application",
       y=NULL,caption="MCC Revenue Administration Reform Project · Quarter ending June 2016 · Indicators 73858–73860") +
  toa_theme() + theme(axis.text.y=element_text(family=toa_fonts[["body"]]),panel.grid.major.y=element_blank())
ggsave("artifacts/philippines_registration.pdf",chart,device=grDevices::cairo_pdf,width=9,height=4.7)
