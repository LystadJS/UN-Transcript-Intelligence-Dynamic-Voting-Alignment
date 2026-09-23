#!/usr/bin/env Rscript
# FIGURE 3 — Venue × Issue Network
# Standalone reproduction script; no shared "make all figures" dependency.
# Theme: State Department / UN-inspired policy-paper styling.
#
# Important: issue halos are interpretive neighborhoods, not exact Euler/Venn
# boundaries. Use Figure 1 / venue_issue_matrix.csv for exact source-coded
# venue-by-issue membership.

required <- c("ggplot2","dplyr","readr","svglite","ragg")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly=TRUE)]
if(length(missing)) stop("Install missing packages: ", paste(missing, collapse=", "))

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(readr)
})

root <- if (length(commandArgs(trailingOnly=TRUE))) commandArgs(trailingOnly=TRUE)[1] else getwd()
data_dir <- file.path(root,"data")
out_dir  <- file.path(root,"output_r")
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)

pal_df <- read_csv(file.path(data_dir,"theme_palette.csv"), show_col_types=FALSE)
pal <- setNames(pal_df$hex,pal_df$element)

nodes <- read_csv(file.path(data_dir,"venue_layout.csv"), show_col_types=FALSE)
halos <- read_csv(file.path(data_dir,"issue_halos.csv"), show_col_types=FALSE)
edges <- read_csv(file.path(data_dir,"network_edges.csv"), show_col_types=FALSE)

num_cols <- c("x","y","label_x","label_y")
nodes[num_cols] <- lapply(nodes[num_cols],as.numeric)
halos[c("cx","cy","width","height","label_x","label_y")] <-
  lapply(halos[c("cx","cy","width","height","label_x","label_y")],as.numeric)
edges[c("shared_count","curve")] <- lapply(edges[c("shared_count","curve")],as.numeric)

stopifnot(nrow(nodes)==20,nrow(halos)==10)
stopifnot(!anyDuplicated(nodes$venue_id))
stopifnot(all(edges$from %in% nodes$venue_id),all(edges$to %in% nodes$venue_id))

ellipse_df <- function(cx,cy,width,height,n=220){
  th <- seq(0,2*pi,length.out=n)
  tibble(x=cx+(width/2)*cos(th), y=cy+(height/2)*sin(th))
}

outer <- bind_rows(lapply(seq_len(nrow(halos)),function(i){
  h <- halos[i,]
  ellipse_df(h$cx,h$cy,h$width,h$height) |>
    mutate(issue_id=h$issue_id, colour=h$colour)
}))
inner <- bind_rows(lapply(seq_len(nrow(halos)),function(i){
  h <- halos[i,]
  ellipse_df(h$cx,h$cy,h$width*.80,h$height*.80) |>
    mutate(issue_id=h$issue_id, colour=h$colour)
}))

edges_xy <- edges |>
  left_join(nodes |> select(venue_id,x,y),by=c("from"="venue_id")) |>
  rename(x=x,y=y) |>
  left_join(nodes |> select(venue_id,x,y),by=c("to"="venue_id")) |>
  rename(xend=x,yend=y)

p <- ggplot() +
  geom_polygon(
    data=outer,aes(x,y,group=issue_id,fill=colour),
    alpha=.17,colour=NA,show.legend=FALSE
  ) +
  geom_polygon(
    data=inner,aes(x,y,group=issue_id,fill=colour),
    alpha=.07,colour=NA,show.legend=FALSE
  ) +
  scale_fill_identity()

# Edge-by-edge curves permit deterministic curvature.
for(i in seq_len(nrow(edges_xy))){
  e <- edges_xy[i,]
  p <- p + geom_curve(
    data=e,aes(x=x,y=y,xend=xend,yend=yend),
    inherit.aes=FALSE,
    curvature=e$curve,
    linewidth=.32+.12*(e$shared_count-1),
    colour=pal[["muted"]],
    alpha=if(e$proposal_involved) .22 else .32,
    linetype=if(e$proposal_involved) "22" else "solid"
  )
}

p <- p +
  geom_point(
    data=nodes |> filter(venue_id!="WAICO"),
    aes(x,y),shape=21,size=5.0,stroke=.7,
    fill=pal[["blue"]],colour="white"
  ) +
  geom_point(
    data=nodes |> filter(venue_id=="WAICO"),
    aes(x,y),shape=21,size=5.0,stroke=.9,
    fill="white",colour=pal[["ink"]]
  ) +
  geom_text(
    data=nodes,aes(x=label_x,y=label_y,label=label),
    hjust=0,vjust=.5,family="sans",
    size=3.35,lineheight=.95,colour=pal[["ink"]]
  ) +
  geom_text(
    data=halos,aes(x=label_x,y=label_y,label=issue_label,colour=colour),
    hjust=0,vjust=0,family="serif",fontface="bold",
    size=4.3,lineheight=.95
  ) +
  geom_text(
    data=halos,aes(x=label_x,y=label_y-.8,label=description),
    hjust=0,vjust=1,family="serif",fontface="italic",
    size=3.05,lineheight=.95,colour=pal[["muted"]]
  ) +
  scale_colour_identity() +
  coord_equal(xlim=c(0,100),ylim=c(0,75),expand=FALSE,clip="off") +
  labs(
    title="AI governance venues cluster across overlapping issue priorities",
    subtitle="Venue-only network using the same 20-venue, 10-issue source-coverage matrix",
    caption=paste0(
      "Note: Halo geometry is a communication device rather than an exact Euler/Venn boundary. ",
      "The Venue × Issue Matrix remains authoritative for exact source-coded coverage. ",
      "Lines are a thinned shared-topic backbone, not formal cooperation or influence."
    )
  ) +
  theme_void(base_family="sans") +
  theme(
    plot.background=element_rect(fill="white",colour=NA),
    plot.title=element_text(
      family="serif",face="bold",colour=pal[["ink"]],
      size=22,margin=margin(b=6)
    ),
    plot.subtitle=element_text(
      colour=pal[["muted"]],size=11.5,margin=margin(b=12)
    ),
    plot.caption=element_text(
      colour=pal[["muted"]],size=8.8,hjust=0,lineheight=1.15,
      margin=margin(t=12)
    ),
    plot.margin=margin(48,26,20,26)
  )

# State/UN policy-paper overline
p <- p +
  annotate("text",x=0,y=79.2,
           label="AI GOVERNANCE / INSTITUTIONAL LANDSCAPE",
           hjust=0,family="sans",fontface="bold",
           size=3.1,colour=pal[["muted"]]) +
  annotate("text",x=100,y=79.2,label="FIGURE 3",
           hjust=1,family="sans",fontface="bold",
           size=3.1,colour=pal[["muted"]]) +
  annotate("segment",x=0,xend=100,y=77.6,yend=77.6,
           colour=pal[["rule"]],linewidth=.3) +
  annotate("segment",x=0,xend=7,y=77.6,yend=77.6,
           colour=pal[["gold"]],linewidth=.8)

ggsave(file.path(out_dir,"Figure_3_Venue_Issue_Network.pdf"),
       p,width=14,height=10.5,device=cairo_pdf,bg="white")
ggsave(file.path(out_dir,"Figure_3_Venue_Issue_Network.svg"),
       p,width=14,height=10.5,device=svglite::svglite,bg="white")
ggsave(file.path(out_dir,"Figure_3_Venue_Issue_Network.png"),
       p,width=14,height=10.5,dpi=400,device=ragg::agg_png,bg="white")
saveRDS(p,file.path(out_dir,"Figure_3_Venue_Issue_Network.rds"))
writeLines(capture.output(sessionInfo()),file.path(out_dir,"sessionInfo.txt"))
