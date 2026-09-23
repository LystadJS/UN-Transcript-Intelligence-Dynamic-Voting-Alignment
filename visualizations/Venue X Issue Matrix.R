# FIGURE 1 — Venue × Issue Matrix

#Environment Setup
required <-
  c(
		"ggplot2",
		"dplyr",
		"readr",
		"svglite",
		"ragg"
	)
missing <- 
	required[!vapply(required, requireNamespace, logical(1), quietly=TRUE)]
if(length(missing)) 
	stop("Install missing packages: ", 
			 paste(
				 missing, 
				 collapse=", "
			 ))
suppressPackageStartupMessages({
  library(ggplot2); 
	library(dplyr); 
	library(readr)
})

root <- 
	if (length(commandArgs(trailingOnly=TRUE))) commandArgs(trailingOnly=TRUE)[1] else getwd()
data_dir <- 
	file.path(root, "data")
out_dir  <- 
	file.path(root, "output_r")
dir.create(
	out_dir, 
	recursive=TRUE, 
	showWarnings=FALSE
)

pal <- # Color palette
	c(
	  ink="#17324D", 
		blue="#1477A8", 
		muted="#5E7182",
	  rule="#D5DFE7", 
		dash="#A4B0BA", 
		pale="#F0F6FA",
	  white="#FFFFFF", 
		gold="#A58A50"
	)

issues <- 
	read_csv(
		file.path(data_dir, "issues.csv"), show_col_types=FALSE) |>
	  mutate(issue_order=as.integer(issue_order)) |> 
		arrange(issue_order)

venues <- 
	read_csv(file.path(data_dir, "venues.csv"), show_col_types=FALSE) |>
  mutate(venue_order=as.integer(venue_order)) |> arrange(venue_order)

cells <- read_csv(file.path(data_dir,"venue_issue_matrix.csv"), show_col_types=FALSE)

issue_theme <- read_csv(file.path(data_dir,"issue_theme.csv"), show_col_types=FALSE)

stopifnot(nrow(venues)==20, nrow(issues)==10, nrow(cells)==200)
stopifnot(!anyDuplicated(paste(cells$venue_id,cells$issue_id)))
stopifnot(all(cells$status %in% c("documented","stated_proposal","not_identified")))

# Row positions with group spacing
venue_pos <- venues |>
  group_by(group_label) |>
  mutate(row_in_group=row_number()) |>
  ungroup()

group_levels <- unique(venues$group_label)
y_cursor <- 0
rows <- list()
for(g in group_levels){
  vg <- venues |> filter(group_label==g)
  y_cursor <- y_cursor + 1.2
  rows[[length(rows)+1]] <- tibble(
    venue_id=vg$venue_id,
    venue_label=vg$venue_label,
    group_label=g,
    y=rev(seq(y_cursor, by=1, length.out=nrow(vg)))
  )
  y_cursor <- max(unlist(lapply(rows, function(x) max(x$y)))) + 0.7
}
row_df <- bind_rows(rows)
# Normalize so first venue is top
row_df <- row_df |> mutate(y=max(y)-y+1)

plot_df <- cells |>
  left_join(row_df |> select(venue_id,venue_label,group_label,y), by="venue_id") |>
  left_join(issues |> select(issue_id,issue_order,issue_label), by="issue_id") |>
  mutate(
    x=issue_order,
    shape=case_when(
      status=="documented" ~ "documented",
      status=="stated_proposal" ~ "proposal",
      TRUE ~ "absent"
    )
  )

# Group headings
group_df <- row_df |>
  group_by(group_label) |>
  summarise(y=max(y)+0.72, .groups="drop")

p <- ggplot(plot_df, aes(x=x,y=y)) +
  # row rules
  geom_hline(
    yintercept=sort(unique(plot_df$y))-0.43,
    colour=pal["rule"], linewidth=.25
  ) +
  # absent marks
  geom_segment(
    data=plot_df |> filter(shape=="absent"),
    aes(x=x-.07,xend=x+.07,y=y,yend=y),
    inherit.aes=FALSE,
    colour=pal["dash"], linewidth=.35
  ) +
  # documented
  geom_point(
    data=plot_df |> filter(shape=="documented"),
    shape=16, size=2.8, colour=pal["blue"]
  ) +
  # proposal
  geom_point(
    data=plot_df |> filter(shape=="proposal"),
    shape=23, size=3.0, stroke=.8,
    fill=pal["white"], colour=pal["blue"]
  ) +
  geom_text(
    data=row_df,
    aes(x=.12,y=y,label=venue_label),
    inherit.aes=FALSE,hjust=0,
    family="sans", size=4.0, colour=pal["ink"]
  ) +
  geom_text(
    data=group_df,
    aes(x=.12,y=y,label=toupper(group_label)),
    inherit.aes=FALSE,hjust=0,
    family="sans", fontface="bold",
    size=3.25, colour=pal["blue"]
  ) +
  scale_x_continuous(
    breaks=issues$issue_order,
    labels=issues$issue_label,
    limits=c(-4.0,10.5),
    position="top",
    expand=c(0,0)
  ) +
  scale_y_continuous(expand=expansion(mult=c(.02,.04))) +
  labs(
    title="AI issues appear in overlapping venues",
    subtitle="Documented topics in 20 selected UN and multilateral profiles",
    caption=paste0(
      "Marks show source coverage—not influence, legal authority, activity levels or policy preferences.\n",
      "A dash is not evidence of absence. WAICO records the agenda stated in its July 2025 proposal.\n",
      "Sources: Appendix III (3 Sep 2026 cutoff) + cited official profiles."
    )
  ) +
  coord_cartesian(clip="off") +
  theme_minimal(base_family="sans") +
  theme(
    plot.background=element_rect(fill="white",colour=NA),
    panel.background=element_rect(fill="white",colour=NA),
    panel.grid=element_blank(),
    axis.title=element_blank(),
    axis.text.y=element_blank(),
    axis.ticks=element_blank(),
    axis.text.x=element_text(
      colour=pal["ink"], face="bold", size=9.5,
      lineheight=.92, margin=margin(b=8)
    ),
    plot.title=element_text(
      family="serif", face="bold", colour=pal["ink"],
      size=22, margin=margin(b=6)
    ),
    plot.subtitle=element_text(
      colour=pal["muted"], size=11.5, margin=margin(b=16)
    ),
    plot.caption=element_text(
      colour=pal["muted"], size=8.8, hjust=0, lineheight=1.18,
      margin=margin(t=14)
    ),
    plot.margin=margin(26,28,20,28)
  )

# Top institutional-landscape overline
p <- p +
  annotate("text", x=-3.95, y=max(plot_df$y)+2.65,
           label="AI GOVERNANCE / INSTITUTIONAL LANDSCAPE",
           hjust=0, family="sans", fontface="bold",
           size=3.0, colour=pal["muted"]) +
  annotate("text", x=10.45, y=max(plot_df$y)+2.65,
           label="FIGURE 1", hjust=1,
           family="sans", fontface="bold",
           size=3.0, colour=pal["muted"]) +
  annotate("segment", x=-3.95,xend=10.45,
           y=max(plot_df$y)+2.35,yend=max(plot_df$y)+2.35,
           linewidth=.3, colour=pal["rule"]) +
  annotate("segment", x=-3.95,xend=-2.75,
           y=max(plot_df$y)+2.35,yend=max(plot_df$y)+2.35,
           linewidth=.8, colour=pal["gold"])

ggsave(file.path(out_dir,"Figure_1_Venue_Issue_Matrix.pdf"),
       p,width=8.5,height=11,device=cairo_pdf,bg="white")
ggsave(file.path(out_dir,"Figure_1_Venue_Issue_Matrix.svg"),
       p,width=8.5,height=11,device=svglite::svglite,bg="white")
ggsave(file.path(out_dir,"Figure_1_Venue_Issue_Matrix.png"),
       p,width=8.5,height=11,dpi=400,device=ragg::agg_png,bg="white")
saveRDS(p,file.path(out_dir,"Figure_1_Venue_Issue_Matrix.rds"))
writeLines(capture.output(sessionInfo()),file.path(out_dir,"sessionInfo.txt"))
