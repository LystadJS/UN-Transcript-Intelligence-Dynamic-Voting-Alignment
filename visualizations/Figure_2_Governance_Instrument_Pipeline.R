# FIGURE 2 — Governance Instrument Pipeline

required <- c("ggplot2","dplyr","readr","svglite","ragg")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly=TRUE)]
if(length(missing)) stop("Install missing packages: ", paste(missing, collapse=", "))

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(readr)
})

root <- if (length(commandArgs(trailingOnly=TRUE))) commandArgs(trailingOnly=TRUE)[1] else getwd()
data_dir <- file.path(root,"data")
out_dir  <- file.path(root,"output_r")
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

pal <- c(
  ink="#17324D", blue="#1477A8", muted="#5E7182",
  rule="#D5DFE7", dash="#A4B0BA", pale="#F0F6FA",
  white="#FFFFFF", gold="#A58A50"
)

routes <- read_csv(file.path(data_dir,"pipeline_routes.csv"), show_col_types=FALSE) |>
  mutate(route_order=as.integer(route_order)) |> arrange(route_order)

stopifnot(nrow(routes)==5)
stopifnot(all(routes$mid_link %in% c("conditional","institutional")))

# Page-coordinate plotting surface.
W <- 320; H <- 240
flip_y <- function(y) H-y

rect_df <- bind_rows(lapply(seq_len(nrow(routes)), function(i){
  y <- 77 + (i-1)*29
  tibble(
    route_id=routes$route_id[i],
    x1=c(73,162), x2=c(143,234),
    y1=flip_y(c(y+12,y+12)),
    y2=flip_y(c(y-12,y-12)),
    box=c("output","step")
  )
}))

p <- ggplot() +
  geom_rect(
    data=rect_df,
    aes(xmin=x1,xmax=x2,ymin=y1,ymax=y2,fill=box),
    colour=NA
  ) +
  scale_fill_manual(values=c(output=pal["pale"],step=pal["white"])) +
  coord_fixed(xlim=c(0,W),ylim=c(0,H),expand=FALSE,clip="off") +
  theme_void(base_family="sans") +
  theme(
    plot.background=element_rect(fill="white",colour=NA),
    legend.position="none",
    plot.margin=margin(0,0,0,0)
  )

# Header
p <- p +
  annotate("text",x=12,y=flip_y(8.7),
           label="AI GOVERNANCE / INSTITUTIONAL LANDSCAPE",
           hjust=0,family="sans",fontface="bold",size=3.0,colour=pal["muted"]) +
  annotate("text",x=W-12,y=flip_y(8.7),
           label="FIGURE 2",hjust=1,family="sans",
           fontface="bold",size=3.0,colour=pal["muted"]) +
  annotate("segment",x=12,xend=W-12,y=flip_y(13),yend=flip_y(13),
           colour=pal["rule"],linewidth=.3) +
  annotate("segment",x=12,xend=31,y=flip_y(13),yend=flip_y(13),
           colour=pal["gold"],linewidth=.8) +
  annotate("text",x=12,y=flip_y(23),
           label="From multilateral text to national practice",
           hjust=0,family="serif",fontface="bold",
           size=7.8,colour=pal["ink"]) +
  annotate("text",x=12,y=flip_y(33),
           label="Five routes to implementation—not one automatic pipeline to binding law",
           hjust=0,family="sans",size=4.1,colour=pal["muted"])

# Legend + headers
p <- p +
  annotate("segment",x=12,xend=22,y=flip_y(44),yend=flip_y(44),
           colour=pal["muted"],linewidth=.45,
           arrow=grid::arrow(length=unit(1.5,"mm"),type="closed")) +
  annotate("text",x=26,y=flip_y(44),label="Institutional relationship",
           hjust=0,family="sans",size=3.5,colour=pal["ink"]) +
  annotate("segment",x=87,xend=97,y=flip_y(44),yend=flip_y(44),
           colour=pal["muted"],linewidth=.45,linetype="22",
           arrow=grid::arrow(length=unit(1.5,"mm"),type="closed")) +
  annotate("text",x=101,y=flip_y(44),label="Further action required",
           hjust=0,family="sans",size=3.5,colour=pal["ink"]) +
  annotate("text",x=189,y=flip_y(44),
           label="Schematic; no timing or adoption rates implied",
           hjust=0,family="sans",size=3.5,colour=pal["muted"])

headers <- tibble(
  x=c(12,73,162,251),
  label=c("VENUE / ROUTE","MULTILATERAL OUTPUT","IMPLEMENTATION STEP","PRACTICAL EFFECT")
)
p <- p +
  geom_text(data=headers,aes(x=x,y=flip_y(56),label=label),
            hjust=0,family="sans",fontface="bold",
            size=3.45,colour=pal["muted"],inherit.aes=FALSE) +
  annotate("segment",x=12,xend=309,y=flip_y(62),yend=flip_y(62),
           colour=pal["ink"],linewidth=.35)

# Routes
for(i in seq_len(nrow(routes))){
  r <- routes[i,]
  y <- 77 + (i-1)*29
  if(i>1){
    p <- p + annotate("segment",x=12,xend=309,
                      y=flip_y(y-14.5),yend=flip_y(y-14.5),
                      colour=pal["rule"],linewidth=.25)
  }

  # box borders
  p <- p +
    annotate("rect",xmin=73,xmax=143,ymin=flip_y(y+12),ymax=flip_y(y-12),
             fill=NA,colour=pal["blue"],linewidth=.32) +
    annotate("rect",xmin=162,xmax=234,ymin=flip_y(y+12),ymax=flip_y(y-12),
             fill=NA,colour=pal["rule"],linewidth=.35)

  # arrows
  arrow_layer <- function(x1,x2,cond=FALSE){
    annotate("segment",x=x1,xend=x2,y=flip_y(y),yend=flip_y(y),
             colour=pal["muted"],linewidth=.42,
             linetype=if(cond) "22" else "solid",
             arrow=grid::arrow(length=unit(1.5,"mm"),type="closed"))
  }
  p <- p + arrow_layer(61,70,FALSE) +
    arrow_layer(146,159,r$mid_link=="conditional") +
    arrow_layer(237,248,TRUE)

  # text
  p <- p +
    annotate("text",x=12,y=flip_y(y-2.6),label=r$venue,hjust=0,
             family="sans",fontface="bold",size=4.2,colour=pal["ink"]) +
    annotate("text",x=12,y=flip_y(y+4.2),label=r$route_label,hjust=0,
             family="sans",size=3.45,colour=pal["muted"]) +
    annotate("text",x=77,y=flip_y(y-5),label=r$output_title,hjust=0,
             family="sans",fontface="bold",size=3.8,colour=pal["ink"]) +
    annotate("text",x=77,y=flip_y(y+3.8),label=r$output_detail,hjust=0,
             family="sans",size=3.45,lineheight=.95,colour=pal["ink"]) +
    annotate("text",x=166,y=flip_y(y-5),label=r$step_title,hjust=0,
             family="sans",fontface="bold",size=3.8,colour=pal["ink"]) +
    annotate("text",x=166,y=flip_y(y+3.8),label=r$step_detail,hjust=0,
             family="sans",size=3.45,lineheight=.95,colour=pal["ink"]) +
    annotate("text",x=251,y=flip_y(y-5),label=r$effect_title,hjust=0,
             family="sans",fontface="bold",size=3.85,colour=pal["ink"]) +
    annotate("text",x=251,y=flip_y(y+3.8),label=r$effect_detail,hjust=0,
             family="sans",size=3.45,lineheight=.95,colour=pal["ink"])
}

p <- p +
  annotate("segment",x=12,xend=309,y=flip_y(214),yend=flip_y(214),
           colour=pal["rule"],linewidth=.3) +
  annotate("text",x=12,y=flip_y(220),
           label="Schematic routes, not measured diffusion. Dashed links require further implementation or legal action; implementation is not automatic.",
           hjust=0,family="sans",size=3.2,colour=pal["muted"]) +
  annotate("text",x=12,y=flip_y(226),
           label="Legal effect belongs to the specific instrument and jurisdiction—not to a venue’s general “Binding” classification.",
           hjust=0,family="sans",size=3.2,colour=pal["muted"]) +
  annotate("text",x=12,y=flip_y(232),
           label="Sources: Appendix III and cited UN, UNESCO, ITU, UNCITRAL and Council of Europe materials.",
           hjust=0,family="sans",size=3.2,colour=pal["muted"])

ggsave(file.path(out_dir,"Figure_2_Governance_Instrument_Pipeline.pdf"),
       p,width=12.6,height=9.45,device=cairo_pdf,bg="white")
ggsave(file.path(out_dir,"Figure_2_Governance_Instrument_Pipeline.svg"),
       p,width=12.6,height=9.45,device=svglite::svglite,bg="white")
ggsave(file.path(out_dir,"Figure_2_Governance_Instrument_Pipeline.png"),
       p,width=12.6,height=9.45,dpi=400,device=ragg::agg_png,bg="white")
saveRDS(p,file.path(out_dir,"Figure_2_Governance_Instrument_Pipeline.rds"))
writeLines(capture.output(sessionInfo()),file.path(out_dir,"sessionInfo.txt"))
