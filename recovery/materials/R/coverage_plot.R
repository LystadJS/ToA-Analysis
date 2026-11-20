# Print companion to the interactive audit. Each cell uses its own provider's definition.
library(data.table)
out <- "artifacts/coverage"
us <- fread(file.path(out,"us-country-year-reconciliation.csv"))
countries <- unique(us[,.(iso3,name)])[order(name)]
cells <- fread(file.path(out,"country-year-observations.csv"))
prc <- cells[provider=="CHN" & kind=="Funding" &
              ((source_id=="gcdf" & series=="adjusted commitment") |
               (source_id=="clg" & series=="face-value commitment (CLG)"))]
stopifnot(!anyDuplicated(prc,by=c("iso3","year")))
us_colors <- c("Amounts agree"="#438979","Higher in sector file"="#edb768","Lower in sector file"="#8fa9cb",
               "Sector file only"="#ae664a","Database only"="#ab91b1","Neither release"="#e6e9e1")
cn_colors <- c("All disclosed"="#438979","Some disclosed"="#edb768","None disclosed"="#ae664a",
               "No country row"="#e6e9e1","Outside releases"="#d1d2da")
years <- 2001:2025
prc[, status := fcase(known==n,"All disclosed",known==0,"None disclosed",default="Some disclosed")]
# Cairo embeds fonts, preserving accented country names.
grDevices::cairo_pdf(file.path(out,"Country-year-coverage.pdf"),width=15,height=10.4)
par(mar=c(0,0,0,0),family="sans",xpd=NA)
count <- 34L
for (first in seq(1,nrow(countries),by=count)) {
  group <- countries[first:min(first+count-1,nrow(countries))]
  plot.new()
  plot.window(xlim=c(0,100),ylim=c(0,100),xaxs="i",yaxs="i")
  text(2,96,"Development finance coverage by recipient and year",adj=0,cex=1.7,font=2,col="#15363a")
  text(2,92.5,"U.S. cells compare fiscal-year disbursements across releases. China cells show the availability of amounts on retained calendar-year commitments.",adj=0,cex=.93)
  panels <- c(USA=20,CHN=60)
  text(20,87.5,"United States  /  sector file versus database",adj=0,cex=1.12,font=2)
  text(60,87.5,"China  /  commitment amount disclosure",adj=0,cex=1.12,font=2)
  text(2,83.6,"Recipient  /  ISO",adj=0,font=2,cex=.81)
  dx <- 1.5
  for (left in panels) {
    pos <- seq_along(years)-1L
    text(left+(pos+.5)*dx,83.6,substring(years,3),cex=.67)
  }
  for (j in seq_len(nrow(group))) {
    code <- group$iso3[j]
    nm <- group$name[j]
    if(nchar(nm)>27L) nm <- paste0(substr(nm,1,25),"...")
    y <- 81.3-(j-1)*1.98
    text(2,y,paste0(nm,"  /  ",code),adj=0,cex=.69)
    a <- us[iso3==code][match(years,year)]$status
    b <- prc[iso3==code][match(years,year)]$status
    b[is.na(b)] <- "No country row"
    b[years>2023] <- "Outside releases"
    stopifnot(!anyNA(a))
    for (provider in names(panels)) {
      x <- panels[[provider]]+(seq_along(years)-1L)*dx
      fill <- if(provider=="USA") us_colors[a] else cn_colors[b]
      rect(x,y-.77,x+dx-.11,y+.77,col=fill,border=NA)
    }
  }
  rect(60+21*dx-.11,15.1,60+21*dx-.05,82.3,col="#455657",border=NA)
  text(2,10.5,"U.S. sector report",adj=0,font=2,cex=.83)
  text(2,7.2,"PRC commitments",adj=0,font=2,cex=.83)
  legend_row <- function(colors,x,y) {
    for(i in seq_along(colors)) {
      rect(x[i],y-.65,x[i]+1.1,y+.65,col=colors[i],border=NA)
      text(x[i]+1.5,y,names(colors)[i],adj=0,cex=.76)
    }
  }
  legend_row(us_colors,c(16,29,44,58,71,82),10.5)
  legend_row(cn_colors,c(16,29,44,58,71),7.2)
  text(2,3.5,"FY2001-25 U.S. government disbursement files. China: AidData GCDF through 2021; CLG in 2022-23. Unobserved cells do not establish zero spending.",adj=0,cex=.76)
  text(98,3.5,sprintf("%d / %d",ceiling(first/count),ceiling(nrow(countries)/count)),adj=1,cex=.76)
}
invisible(dev.off())
