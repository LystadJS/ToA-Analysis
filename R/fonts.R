toa_fonts <- c(title="EB Garamond", body="Atkinson Hyperlegible Next", number="JetBrains Mono")

# Embed the same licensed font files in each standalone HTML release.
web_fonts_css <- function() {
  css <- vapply(toa_fonts,function(family) {
    stem <- file.path("assets","fonts",gsub(" ","",family,fixed=TRUE))
    file <- paste0(stem,".ttf")
    encoded <- jsonlite::base64_enc(readBin(file,"raw",n=file.size(file)))
    license <- paste(readLines(paste0(stem,"-OFL.txt"),warn=FALSE),collapse="\n")
    weights <- if (family=="EB Garamond") "400 800" else if (family=="Atkinson Hyperlegible Next") "200 800" else "100 800"
    paste0("/* ",license," */\n@font-face{font-family:'",family,"';font-style:normal;font-weight:",
           weights,";font-display:swap;src:url(data:font/ttf;base64,",
           gsub("\n","",encoded,fixed=TRUE),") format('truetype')}")
  },character(1))
  paste(c(css,":root{--serif:'EB Garamond',serif;--sans:'Atkinson Hyperlegible Next',sans-serif;--mono:'JetBrains Mono',monospace;--plot-grid:#dedede;--plot-minor:#f0f0f0}"),collapse="\n")
}
