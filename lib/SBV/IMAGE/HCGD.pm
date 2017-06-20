package SBV::IMAGE::HCGD;
#-------------------------------------------------+
#    [APM] This moudle was generated by amp.pl    |
#    [APM] Created time: 2014-09-18 14:20:50      |
#-------------------------------------------------+
=pod

=head1 Name

SBV::IMAGE::HCGD

=head1 Synopsis

This module is not meant to be used directly

=head1 Feedback

Author: Peng Ai
Email:  aipeng0520@163.com

=head1 Version

Version history

=head2 v1.0

Date: 2014-09-18 14:20:50

=cut


use strict;
use warnings;
require Exporter;


use Math::Cephes qw(:trigs);
use Math::Round;

use FindBin;
use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/lib";
use lib "$FindBin::RealBin/..";
use lib "$FindBin::RealBin/../lib";

use SBV::STAT qw/max/;
use SBV::Constants;
use SBV::DEBUG;
use SBV::Colors;

sub new 
{
	my ($class,$data,$conf) = @_;
	my $object = {};
	$object->{data} = _read_cytoBand($data);
	$object->{conf} = $conf;
	bless $object , $class;
	return $object;
}

sub plot
{
	my ($self,$parent,%opts) = @_;
	my $conf = $self->{conf};
	$self->{parent} = $parent;
	my $model = $opts{model} || $conf->{model};
	SBV::DRAW::background($conf,$parent);
	my $group = $parent->group(id=>"karyo$SBV::idnum");
	$SBV::idnum ++;
	$self->{group} = $group;
	
	$self->_hcgd();

	# add legend
	if ($conf->{legend})
	{
		my $legend = SBV::STONE::LEGEND->new(conf=>$conf->{legend});
		$legend->location($conf);
		$legend->draw($parent);
	}
}

sub _hcgd
{
	my $self = shift;

	my $data = $self->{data};
	my $conf = $self->{conf};
	my $group = $self->{group};
	
	$data = parse_ticks($data,$conf);
	$data = parse_highlights($data,$conf);
	my @plots = SBV::IMAGE::KARYO::parse_plots($conf);

	my $model = $conf->{model};

	# fetch the chrs 
	my @chrs = map { "chr" . $_ } 1 .. 22;
	push @chrs , "chrX";
	push @chrs , "chrY";
	
	@chrs = sort keys %$data if (! $conf->{human});

	if ($conf->{chromosomes_order})
	{
		@chrs = split /;/ , $conf->{chromosomes_order};
	}
	
	# the maximun chromosomes number of each row allowed
	my $ncol = $conf->{col_chr_number};
	my $row_chr_spacing = $conf->{row_chr_spacing};
	my $unit_chr_width = $ncol < $#chrs+1 ? nearest 0.01 , $conf->{tw} / $ncol : nearest 0.01 , $conf->{tw} / ($#chrs+1);
	my $thickness = $conf->{thickness};
	my $chr_rounded_ratio = $conf->{chr_rounded_ratio};

	if ($chr_rounded_ratio >= 0.5 || $chr_rounded_ratio < 0)
	{
		ERROR('chr_round_ratio_err');
	}

	my $ry = nearest 0.01 , $thickness*$chr_rounded_ratio;
	
	# calculate the row number 
	# int (($#chrs + 1 - 1)/$ncol) + 1
	my $nrow = int ($#chrs/$ncol) + 1;
	
	#init the chromosomes style 
	my $style = "stroke:#000;stroke-width:1;fill:none";
	
	# fetch the label style 
	my $label_font = SBV::Font->new($conf->{label_theme});
	my $label_h = $label_font->fetch_text_height;
	my $label_style = $label_font->toStyle();
	my $hi = $SBV::conf->{hspace};
	my $vi = $SBV::conf->{vspace};
	
	# calculate the zoom size of chromosomes
	my $sum = $conf->{th} - $nrow*($row_chr_spacing+$label_h+$vi) + $row_chr_spacing;
	my $zoom = _fetch_chr_zoom($conf,$sum,$data,$nrow,$ncol,@chrs);
	my $offset = SBV::CONF::fetch_size($conf->{offset},$unit_chr_width);
	
	#  save the chr end y position 
	my %yloci;

	# define the G-banding animate
	my $js = <<JS;
var svgdoc;
var svgns = "http://www.w3.org/2000/svg";
var isIE = document.all?true:false;
var style = "";
var text;

function blockMouseOver(evt)
{
	svgdoc = evt.target.ownerDocument;
	var block = evt.target;
	
	style = block.getAttribute("style");
	block.setAttribute("style","fill:red;stroke-width:0");
}

function blockMouseOut(evt)
{
	svgdoc = evt.target.ownerDocument;
	var block = evt.target;
	
	block.setAttribute("style",style);
}
JS
	$SBV::svg->script(type=>"text/javascript")->CDATA($js) if ($conf->{animate});

	# draw the chromosomes
	my $x = $conf->{ox} + $offset;
	my $y = $conf->{oty};
	A: for my$i ( 0 .. $nrow-1 )
	{
		my $max_size = 0;
		$x = $conf->{ox} + $offset;
		B: for my$j ( 0 .. $ncol-1 )
		{
			my $index = $i * $ncol + $j;
			last A if ($index > $#chrs);

			# fetch the x and y
			my $chr = $chrs[$index];
			my $size = $data->{$chr}->{size};
			my $height = nearest 0.01 , $size * $zoom;
			$max_size = $size if $max_size < $size;

			my $chr_group = $group->group(class=>"$chr");

			# draw label 
			my $label = $chr;
			$label =~ s/chr//;
			my $label_w = $label_font->fetch_text_width($label);
			
			my $chr_y;
			if ($conf->{dense} && $i >0 && $nrow == 2)
			{
				$chr_y = $conf->{oy} - $vi - $label_h - $height;
				$chr_group->text(x=>$x+$thickness/2-$label_w/2,y=>$conf->{oy},style=>$label_style)->cdata($label);
			}
			elsif ($conf->{dense} && $i > 0)
			{
				my $pre_index = ($i-1)*$ncol + $j;
				my $pre_chr = $chrs[$pre_index];
				$chr_y = $data->{$pre_chr}->{oy} + $data->{$pre_chr}->{height} + $row_chr_spacing + $label_h + $vi;
				$chr_group->text(x=>$x+$thickness/2-$label_w/2,y=>$chr_y-$vi,style=>$label_style)->cdata($label);
			}
			else 
			{
				$chr_y = nearest 0.01 , $y+$label_h+$vi;
				$chr_group->text(x=>$x+$thickness/2-$label_w/2,y=>$chr_y-$vi,style=>$label_style)->cdata($label);
			}
			
			$data->{$chr}->{oy} = $chr_y;
			$data->{$chr}->{x1} = $x;
			$data->{$chr}->{x2} = $x + $thickness;
			$data->{$chr}->{height} = $height;
			
			# draw ticks 
			my$ticks = $data->{$chr}->{ticks};
			if ($ticks && $conf->{show_ticks})
			{
				foreach my$tick (@$ticks)
				{
					my $orientation = $tick->{orientation} || "left";
					my $offset = $tick->{offset} || 0;
					my $bone = 0 == $offset ? 0 : 1;
					my $transx;
					my $transy = $chr_y;
					my $side;

					if ($orientation eq "left")
					{
						$transx = $x - $offset;
						$side = "right";
					}
					elsif ($orientation eq "down") 
					{
						$transx = $x + $thickness + $offset;
						$side = "left";
					}
					else 
					{
						ERROR('ticks_orientation_err',$orientation);
					}

					my $tickObj = $chr_group->group(class=>"ticks",transform=>"translate($transx,$transy)");
					my $axis = SBV::STONE::AXIS->new(ox=>0,oy=>0,angle=>90,length=>$height,bone=>$bone,
						size=>$tick->{size},start=>0,show_tick_label=>$tick->{show_label},side=>$side,
						tick=>"0 $data->{$chr}->{size} $tick->{spacing}",skip_first_tick=>0,unit_label=>$tick->{unit_label},
						multiple=>$tick->{label_multiplier},parent=>$tickObj,theme=>$tick->{tick_label_theme});
					
					$axis->plot();
				}
			}

# define the clip path for G-banding highlights
			my $clip_id = "clip_path_$chr";
			my $clip = $SBV::defs->clipPath(id=>$clip_id,style=>"evenodd",clipPathUnits=>"UserSpaceOnUse");
			if ($model eq "normal")
			{
				my @clipx = ($x,$x+$ry,$x+$thickness-$ry,$x+$thickness,$x+$thickness,$x+$thickness-$ry,$x+$ry,$x);
				my @clipy = ($chr_y+$ry,$chr_y,$chr_y,$chr_y+$ry,$chr_y+$height-$ry,$chr_y+$height,$chr_y+$height,$chr_y+$height-$ry);
				$clip->path(d=>"M$clipx[0] $clipy[0] \
A$ry $ry 90 0 1 $clipx[1] $clipy[1] L$clipx[2] $clipy[2] \
A$ry $ry 90 0 1 $clipx[3] $clipy[3] L$clipx[4] $clipy[4] \
A$ry $ry 90 0 1 $clipx[5] $clipy[5] L$clipx[6] $clipy[6] \
A$ry $ry 90 0 1 $clipx[7] $clipy[7] Z");
			
# draw highlights (G-banding region)
				foreach (@{$data->{$chr}->{blocks}})
				{
					my ($sta,$end,$name,$type) = @{$_};
					my $hl_y = nearest 0.01 , $chr_y + $sta * $zoom;
					my $hl_h = nearest 0.01 , ($end-$sta) * $zoom;
					my $color = SBV::Colors::fetch_color($type);
					
					if ($hl_y < $chr_y + $ry || $hl_y+$hl_h > $chr_y+$height)
					{
						
						$chr_group->rect(x=>$x,y=>$hl_y,width=>$thickness,height=>$hl_h,
						style=>"fill:$color;stroke-width:0",
						"onmouseover"=>"blockMouseOver(evt)","onmouseout"=>"blockMouseOut(evt)",
						"clip-path"=>"url(#$clip_id)");
					}
					else 
					{
						$chr_group->rect(x=>$x,y=>$hl_y,width=>$thickness,height=>$hl_h,
						"onmouseover"=>"blockMouseOver(evt)","onmouseout"=>"blockMouseOut(evt)",
						style=>"fill:$color;stroke-width:0");
					}
				}
				
				# draw chromosomes bar
				$chr_group->rect(x=>$x,y=>$chr_y,width=>$thickness,height=>$height,
					style=>$style,rx=>$thickness*$chr_rounded_ratio,ry=>$thickness*$chr_rounded_ratio);
			}
			elsif ($model eq "NCBI")
			{
				my @blocks;
				my ($y1,$y2);
				my $frt = 1; # set a flag for acen
				$y1 = 0;
				foreach (@{$data->{$chr}->{blocks}})
				{
					my ($sta,$end,$name,$type) = @{$_};
					my $hl_y = nearest 0.01 , $chr_y + $sta * $zoom;
					my $hl_h = nearest 0.01 , ($end-$sta) * $zoom;

					if ($type eq "stalk")
					{
						my $hl_y1 = $hl_y + $hl_h/3;
						my $hl_y2 = $hl_y1 + $hl_h/3;
						$chr_group->line(x1=>$x,x2=>$x+$thickness,y1=>$hl_y1,y2=>$hl_y1,style=>"stroke-width:1;stroke:#000");
						$chr_group->line(x1=>$x,x2=>$x+$thickness,y1=>$hl_y2,y2=>$hl_y2,style=>"stroke-width:1;stroke:#000");

						push @blocks , [$y1,$y2];
						$y1 = $end;
					}
					elsif ($type eq "gvar")
					{
						$y2 = $end;
						
						# repalce the skew lines with color
						my $color = SBV::Colors::fetch_color($type);
						$chr_group->rect(x=>$x,y=>$hl_y,width=>$thickness,height=>$hl_h,
						style=>"fill:$color;stroke-width:0",
						"onmouseover"=>"blockMouseOver(evt)","onmouseout"=>"blockMouseOut(evt)",
						"clip-path"=>"url(#$clip_id)");
					}
					elsif ($type eq "acen")
					{
						# repalce the skew lines with color
						my $color = SBV::Colors::fetch_color($type);
						my $ratation = 90;
						if ($frt == 1)
						{
							$y2 = $end;
							push @blocks , [$y1,$y2];
							$y1 = $end;
							$frt = 0;
=pep							
							my @px = ($x,$x,$x+$ry,$x+$thickness-$ry,$x+$thickness,$x+$thickness);
							my @py = ($hl_y,$hl_y+$hl_h-$ry,$hl_y+$hl_h,$hl_y+$hl_h,$hl_y+$hl_h-$ry,$hl_y);
							
							if ($hl_h < $ry)
							{
								$px[0] = $x + $ry - sqrt($ry**2 + ($ry- $hl_h)**2);
								$px[1] = $px[0];
								$px[4] = $x + $thickness - $ry + sqrt($ry**2 + ($ry- $hl_h)**2);
								$px[5] = $px[4];

								$py[1] = $py[0];
								$py[4] = $py[5];
								$ratation = 360*asin(($ry-$hl_h)/$ry)/$TWOPI;
							}

							my $path = "M$px[0] $py[0] L$px[1] $py[1] A$ry $ry $ratation \
0 0 $px[2] $py[2] L$px[3] $py[3] A$ry $ry $ratation 0 0 $px[4] $py[4] L$px[5] $py[5] Z";
							$chr_group->path(d=>$path,style=>"fill:$color;stroke-width:0");
=cut
						}
						else 
						{
							$y2 = $end;
							$frt = 1;

=pep
							my @px = ($x,$x,$x+$ry,$x+$thickness-$ry,$x+$thickness,$x+$thickness);
							my @py = ($hl_y+$hl_h,$hl_y+$ry,$hl_y,$hl_y,$hl_y+$ry,$hl_y+$hl_h);

							if ($hl_h < $ry)
							{
								$px[0] = $x + $ry - sqrt($ry**2 + ($ry- $hl_h)**2);
								$px[1] = $px[0];
								$px[4] = $x + $thickness - $ry + sqrt($ry**2 + ($ry- $hl_h)**2);
								$px[5] = $px[4];

								$py[1] = $py[0];
								$py[4] = $py[5];
								$ratation = 360*asin(($ry-$hl_h)/$ry)/$TWOPI;
							}

							my $path = "M$px[0] $py[0] L$px[1] $py[1] A$ry $ry $ratation \
0 1 $px[2] $py[2] L$px[3] $py[3] A$ry $ry $ratation 0 1 $px[4] $py[4] L$px[5] $py[5] Z";
							$chr_group->path(d=>$path,style=>"fill:$color;stroke-width:0");
=cut

						}
						
						$chr_group->rect(x=>$x,y=>$hl_y,width=>$thickness,height=>$hl_h,
						style=>"fill:$color;stroke-width:0",
						"onmouseover"=>"blockMouseOver(evt)","onmouseout"=>"blockMouseOut(evt)",
						"clip-path"=>"url(#$clip_id)");
					}
					else 
					{
						$y2 = $end;
						my $color = SBV::Colors::fetch_color($type);
						$chr_group->rect(x=>$x,y=>$hl_y,width=>$thickness,height=>$hl_h,
						style=>"fill:$color;stroke-width:0",
						"onmouseover"=>"blockMouseOver(evt)","onmouseout"=>"blockMouseOut(evt)",
						"clip-path"=>"url(#$clip_id)");
					}
				}
				push @blocks , [$y1,$y2];
				
				my $tmpx = $x + $thickness/2;
				my $clip_path = "M$tmpx $chr_y ";
				my @clipx = ($x,$x+$ry,$x+$thickness/2,$x+$thickness-$ry,$x+$thickness);
				my @clipy;
				# draw chromosomes bar
				foreach (@blocks)
				{
					my ($sta,$end) = @$_;
					$chr_group->rect(x=>$x,y=>$chr_y+$sta*$zoom,width=>$thickness,height=>($end-$sta)*$zoom,
						style=>$style,rx=>$thickness*$chr_rounded_ratio,ry=>$thickness*$chr_rounded_ratio);

					my $y1 = nearest 0.01 , $chr_y + $sta*$zoom;
					my $y2 = nearest 0.01 , $chr_y + $end*$zoom;
					splice (@clipy,$#clipy+1,0,($y1,$y1,$y1+$ry,$y2-$ry,$y2,$y2));
				}
				
				for my$i( 0 .. $#blocks )
				{
					my $index = $i * 6;

					if ($i % 2 == 0) # left side 
					{
						$clip_path .= "L$clipx[2] $clipy[$index] L$clipx[1] $clipy[$index+1] \
A$ry $ry 90 0 0 $clipx[0] $clipy[$index+2] L$clipx[0] $clipy[$index+3] \
A$ry $ry 90 0 0 $clipx[1] $clipy[$index+4] L$clipx[2] $clipy[$index+5] ";
					}
					else # right side 
					{
						$clip_path .= "L$clipx[2] $clipy[$index] L$clipx[3] $clipy[$index+1] \
A$ry $ry 90 0 1 $clipx[4] $clipy[$index+2] L$clipx[4] $clipy[$index+3] \
A$ry $ry 90 0 1 $clipx[3] $clipy[$index+4] L$clipx[2] $clipy[$index+5] ";
					}
				}

				for (my$i=$#blocks;$i>=0;$i--)
				{
					my $index = $i * 6;
					if ($i % 2 == 0) # right side
					{
						$clip_path .= "L$clipx[2] $clipy[$index+5] L$clipx[3] $clipy[$index+4] \
A$ry $ry 90 0 0 $clipx[4] $clipy[$index+3] L$clipx[4] $clipy[$index+2] \
A$ry $ry 90 0 0 $clipx[3] $clipy[$index+1] L$clipx[2] $clipy[$index] ";
					}
					else # left side
					{
						$clip_path .= "L$clipx[2] $clipy[$index+5] L$clipx[1] $clipy[$index+4] \
A$ry $ry 90 0 1 $clipx[0] $clipy[$index+3] L$clipx[0] $clipy[$index+2] \
A$ry $ry 90 0 1 $clipx[1] $clipy[$index+1] L$clipx[2] $clipy[$index] ";
					}
				}

				$clip_path .= "Z";
				$clip->path(d=>$clip_path);
			}
			elsif($model eq "Ensembl")
			{
				my ($y1,$y2);
				my $frt = 1; # set a flag for acen
				$y1 = 0;
				
				my @clipx = ($x,$x+$ry,$x+$thickness/2,$x+$thickness-$ry,$x+$thickness);
				my @clipy = ($chr_y,$chr_y+$ry,$chr_y+$height-$ry,$chr_y+$height);
				my @othery;

				foreach (@{$data->{$chr}->{blocks}})
				{
					my ($sta,$end,$name,$type) = @{$_};
					my $hl_y = nearest 0.01 , $chr_y + $sta * $zoom;
					my $hl_h = nearest 0.01 , ($end-$sta) * $zoom;

					if ($type eq "stalk")
					{
						push @othery , ["stalk",$hl_y,$hl_y+$hl_h];
						
						my $color = SBV::Colors::fetch_color($type);
						$chr_group->rect(x=>$x,y=>$hl_y,width=>$thickness,height=>$hl_h,
						style=>"fill:$color;stroke-width:0",
						"onmouseover"=>"blockMouseOver(evt)","onmouseout"=>"blockMouseOut(evt)",
						"clip-path"=>"url(#$clip_id)");
					}
					elsif ($type eq "acen")
					{
						if ($frt == 1)
						{
							$frt = 0;
							push @othery , ["acen1",$hl_y,$hl_y+$hl_h];
						}
						else 
						{
							push @othery , ["acen2",$hl_y,$hl_y+$hl_h];
						}

						my $color = SBV::Colors::fetch_color($type);
						$chr_group->rect(x=>$x,y=>$hl_y,width=>$thickness,height=>$hl_h,
						style=>"fill:$color;stroke-width:0",
						"onmouseover"=>"blockMouseOver(evt)","onmouseout"=>"blockMouseOut(evt)",
						"clip-path"=>"url(#$clip_id)");
					}
					else 
					{
						my $color = SBV::Colors::fetch_color($type);
						$chr_group->rect(x=>$x,y=>$hl_y,width=>$thickness,height=>$hl_h,
						style=>"fill:$color;stroke-width:0",
						"onmouseover"=>"blockMouseOver(evt)","onmouseout"=>"blockMouseOut(evt)",
						"clip-path"=>"url(#$clip_id)");
					}
				}

				my $clip_path = "M$clipx[1] $clipy[0] A$ry $ry 90 0 0 $clipx[0] $clipy[1] ";

				foreach (@othery)
				{
					my ($type,$stay,$endy) = @$_;
					if ($type eq "stalk")
					{
						$clip_path .= "L$clipx[0] $stay L$clipx[1] $stay L$clipx[1] $endy L$clipx[0] $endy ";
					}
					elsif ($type eq "acen1")
					{
						$clip_path .= "L$clipx[0] $stay L$clipx[2] $endy ";
					}
					elsif ($type eq "acen2")
					{
						$clip_path .= "L$clipx[0] $endy ";
					}
				}

				$clip_path .= "L$clipx[0] $clipy[2] A$ry $ry 90 0 0 $clipx[1] $clipy[3] L
$clipx[3] $clipy[3] A$ry $ry 90 0 0 $clipx[4] $clipy[2] ";
				
				foreach (reverse @othery)
				{
					my ($type,$stay,$endy) = @$_;
					if ($type eq "acen2")
					{
						$clip_path .= "L$clipx[4] $endy L$clipx[2] $stay ";
					}
					elsif ($type eq "acen1")
					{
						$clip_path .= "L$clipx[4] $stay ";
					}
					elsif ($type eq "stalk")
					{
						$clip_path .= "L$clipx[4] $endy L$clipx[3] $endy L$clipx[3] $stay L$clipx[4] $stay ";
					}
				}
				
				$clip_path .= "L$clipx[4] $clipy[1] A$ry $ry 90 0 0 $clipx[3] $clipy[0] Z";
				$clip->path(d=>$clip_path);
				$chr_group->path(d=>$clip_path,style=>$style);
			}
			
			# draw highlights
			if (my$highlights = $data->{$chr}->{highlights})
			{
				foreach my$hl (@$highlights)
				{
					my ($hl_x,$hl_y,$hl_w,$hl_h,$shape);

					if ($hl->{ideogram})
					{
						$hl_x = $x;
						$hl_w = $thickness;
					}
					else
					{
						my ($loc0,$loc1) = ($hl->{loc0},$hl->{loc1});
						$loc0 = $loc0 < 0  ? $x + $loc0 : $x + $thickness + $loc0;
						$loc1 = $loc1 < 0  ? $x + $loc1 : $x + $thickness + $loc1;
						($loc0,$loc1) = ($loc1,$loc0) if ($loc0 > $loc1);
						$hl_x = $loc0;
						$hl_w = $loc1 - $loc0;
					}

					my ($sta,$end) = ($hl->{start},$hl->{end});
					$hl_y = $chr_y + $zoom*$sta;
					$hl_h = ($end-$sta)*$zoom;
					
					my $hlg;
					if ($hl->{shape} == 0)
					{
						my $color = fetch_color($hl->{color});
						my $fill = fetch_color($hl->{fill});
						$hlg = $chr_group->rect(x=>$hl_x,y=>$hl_y,width=>$hl_w,height=>$hl_h,
							style=>"stroke:$color;stroke-width:$hl->{stroke_width};fill:$fill;");
					}
					elsif ($sta == $end && $hl->{shape} == 17)
					{
						$hlg = $chr_group->line(x1=>$hl_x,x2=>$hl_x+$hl_w,y1=>$hl_y,y2=>$hl_y,
							style=>"stroke:$hl->{stroke};stroke-width:$hl->{stroke_width}");
					}
					else 
					{
						if ($sta == $end)
						{
							$hl_h = $hl->{radius} ? $hl->{radius} * 2 : 4;
							$hl_y -= $hl_h/2;
						}

						delete $hl->{width};
						delete $hl->{height};

						my $symid = SBV::STONE::SYMBOL::new($hl->{shape},width=>$hl_w,height=>$hl_h,%$hl);
						$hlg = $chr_group->group(class=>"highlights")->use(x=>$hl_x,y=>$hl_y,width=>$hl_w,height=>$hl_h,'-href'=>"#$symid");
					}
					
					$hlg->setAttribute("clip-path","url(#$clip_id)") if ($hl->{ideogram});
				}
			}
				

			$x += $unit_chr_width;
		}

		$y += $max_size * $zoom + $row_chr_spacing + $label_h + $vi;
	}

	# _add_plots
	my $plotsObj = $group->group(class=>"plots");
	foreach my$plot(sort {$a->{z} <=> $b->{z}} @plots)
	{
		my $plotObj = $plotsObj->group(class=>"plot");
	
		foreach my$chr(keys %{$plot->{data}})
		{
			#next unless defined $data->{$chr}->{display};
			_add_plot($data,$plot,$chr,$zoom,$plotObj);
		}
	}

}

sub _fetch_chr_zoom
{
	my ($conf,$sum,$data,$nrow,$ncol,@chrs) = @_;

	my $max = 0;

	if ($conf->{dense})
	{
		my @tmp;
		for my$j (0 .. $ncol-1)
		{
			foreach my $i ( 0 .. $nrow-1 )
			{
				my $index = $i*$ncol + $j;
				next if $index > $#chrs;
				
				my $chr = $chrs[$index];
				$tmp[$j] += $data->{$chr}->{size}
			}
		}

		$max = max(\@tmp);
	}
	else 
	{
		A: for my$i(0 .. $nrow-1)
		{
			my @tmp;
			B: for my$j( 0 .. $ncol-1 )
			{
				my $index = $i*$ncol + $j;
				last B if $index > $#chrs;
				
				my $chr = $chrs[$index];
				push @tmp , $data->{$chr}->{size};
			}
		
			$max += max(\@tmp);
		}
	}

	my $zoom = $sum/$max;
	return $zoom;
}

# read the data 
sub _read_cytoBand
{
	my $file = shift;
	my $hash = {};
	
	my %loci;
	open FH,$file or die $!;
	while(<FH>)
	{
		chomp;
		my ($chr,$sta,$end,$name,$type) = split;
		push @{$hash->{$chr}->{blocks}} , [$sta,$end,$name,$type];
		$loci{$chr}->{$sta} = $type;
		$loci{$chr}->{$end} = $type;
	}
	close FH;

	foreach my$chr(keys %loci)
	{
		my @locis = sort { $a<=>$b } keys %{$loci{$chr}};
		$hash->{$chr}->{size} = $locis[-1];
	}

	return $hash;
}

# parse ticks block in conf 
sub parse_ticks
{
	my ($data,$conf) = @_;

	return $data unless ($conf->{ticks});
	my $ticks = SBV::CONF::fetch_first_conf('ticks',$conf);
	return $data unless ($ticks->{tick});
	
	if (ref $ticks->{tick} eq "ARRAY")
	{
		foreach my$tick (@{$ticks->{tick}})
		{
			$data = _parse_tick($data,$ticks,$tick);
		}
	}
	else 
	{
		$data = _parse_tick($data,$ticks,$ticks->{tick});
	}

	return $data;
}

# parse tick block in conf 
sub _parse_tick
{
	my ($data,$conf,$subconf) = @_;
	
	# inherit attr from ticks
	foreach my$key (keys %$conf)
	{
		next if ($key eq "tick");
		$subconf->{$key} = $conf->{$key} unless $subconf->{$key};
	}

	my $show = {};
	if ($subconf->{chromosomes})
	{
		my @chrs = split /;/ , $subconf->{chromosomes};
		
		foreach my$chr(@chrs)
		{
			if ($chr =~ /^-/)
			{
				$show->{$chr} = 0;
			}
			else 
			{
				$show->{$chr} = 1;
			}
		}
	}
	else 
	{
		$show->{$_} = 1 foreach (keys %$data);
	}

	foreach my$chr(keys %$data)
	{
		push @{$data->{$chr}->{ticks}} , $subconf if ($show->{$chr});
	}

	return $data;
}

# parse highlights block in conf 
sub parse_highlights
{
	my ($data,$conf) = @_;

	return $data unless ($conf->{highlights});
	$conf = SBV::CONF::fetch_first_conf("highlights",$conf);
	return $data unless ($conf->{highlight});
	
	if (ref $conf->{highlight} eq "ARRAY")
	{
		foreach my$subconf (@{$conf->{highlight}})
		{
			$data = _parse_highlight($data,$conf,$subconf);
		}
	}
	elsif (ref $conf->{highlight} eq "HASH")
	{
		$data = _parse_highlight($data,$conf,$conf->{highlight});
	}
	
	return $data;
}


sub _parse_highlight
{
	my ($data,$conf,$subconf) = @_;
	return $data unless $subconf->{file};
	my $file = check_path($subconf->{file});

	# inherit attr from ticks
	foreach my$key (keys %$conf)
	{
		next if ($key eq "highlight");
		$subconf->{$key} = $conf->{$key} unless $subconf->{$key};
	}

	# read highlights file 
	open FH,$file or die;
	while(<FH>)
	{
		chomp;
		next if (/^#/);
		next if ($_ eq "");
		my ($chr,$sta,$end,$attrs) = split;
		next unless ($data->{$chr});

		my $attrs_hash = {};
		foreach my$name(keys %$subconf)
		{
			$attrs_hash->{$name} = $subconf->{$name} unless ($name eq "file");
		}

		($sta,$end) = ($end,$sta) if ($sta > $end);
		$attrs_hash->{start} = $sta;
		$attrs_hash->{end} = $end;
		
		if ($attrs)
		{
			my @attrs = split /;/ , $attrs;
			foreach my$attr(@attrs)
			{
				my ($name,$val) = split /=/ , $attr;
				$val = SBV::Colors::fetch_color($val) if ($name eq "color" || $name eq "fill");
				$attrs_hash->{$name} = $val;
			}
		}

		push @{$data->{$chr}->{highlights}} , $attrs_hash;
	}

	close FH;

	return $data;
}

# add plot to normal karyotype figure
sub _add_plot
{
	my ($data,$plot,$chr,$zoom,$parent)	= @_;

	my $type = $plot->{type};
	my %func = (
		scatter   => \&_add_scatter_plot,
		line      => \&_add_line_plot,
		histogram => \&_add_histogram_plot,
		heatmap   => \&_add_heatmap_plot,
		text      => \&_add_text_plot,
	);
	
	ERROR('err_plot_type') unless defined $func{$type};

	my $child = $parent->group(class=>"$chr\_plot");
	&{$func{$type}}($data,$plot,$chr,$zoom,$child);
}

# add scatter diagram
sub _add_scatter_plot
{
	my ($data,$plot,$chr,$zoom,$parent) = @_;
	my $records = $plot->{data}->{$chr};
	
	# get the min and max value of the data
	my @vals = map { $$_[2] } @$records;
	my $min = defined $plot->{min} ? $plot->{min} : min(\@vals);
	my $max = defined $plot->{max} ? $plot->{max} : max(\@vals);
	my $tick = SBV::STAT::dividing($min,$max,-xtrue=>1);
	my $show_tick_label = $plot->{show_tick_label} || 0;
	my $show_tick_line = $plot->{show_tick_line} || 0;

	# create the x axis for val
	my $x1 = cal_x_coord($data,$chr,$plot->{loc0});
	my $x2 = cal_x_coord($data,$chr,$plot->{loc1});
	my $len = abs ($x1 - $x2);
	my $axis = SBV::STONE::AXIS->new(
		oy=>$data->{$chr}->{oy},ox=>$x1,length=>$len,
		tick=>$tick,
		show_tick_label=>$show_tick_label,
		show_tick_line=>$show_tick_line,
		skip_first_tick => 0,
		skip_last_tick => 0,
		size=>8,
		side=>"left",
	);
	$axis->plot(parent=>$parent);
	#add_background_and_axis($axis,$plot,$data->{$chr}->{width});

	foreach (@$records)
	{
		my ($sta,$end,$val,$attrs) = @$_;
		my $y = nearest 0.01 , $data->{$chr}->{oy} + ($sta+$end)*$zoom/2;
		next if ($val > $max || $val < $min);
		my $dis = $axis->fetch_dis($val);
		my $x = $x1 < $x2 ? $x1 + $dis : $x1 - $dis;
		my $radius = $attrs->{radius} || 2;
		my $shape = defined $attrs->{shape} ? $attrs->{shape} : 1;
		my $style = SBV::CONF::fetch_styles(%$attrs);
		$parent->circle(cx=>$x,cy=>$y,r=>$radius,style=>$style);
	}
}

sub _add_line_plot
{
	my ($data,$plot,$chr,$zoom,$parent) = @_;
	my $records = $plot->{data}->{$chr};

	# get the min and max value of the data
	my @vals = map { $$_[2] } @$records;
	my $min = defined $plot->{min} ? $plot->{min} : min(\@vals);
	my $max = defined $plot->{max} ? $plot->{max} : max(\@vals);
	my $tick = SBV::STAT::dividing($min,$max,-xtrue=>1);
	my $show_tick_label = $plot->{show_tick_label} || 0;
	my $show_tick_line = $plot->{show_tick_line} || 0;

	# create the x axis for val
	my $x1 = cal_x_coord($data,$chr,$plot->{loc0});
	my $x2 = cal_x_coord($data,$chr,$plot->{loc1});
	my $len = abs ($x1 - $x2);
	my $axis = SBV::STONE::AXIS->new(
		oy=>$data->{$chr}->{oy},ox=>$x1,length=>$len,
		tick=>$tick,
		show_tick_label=>$show_tick_label,
		show_tick_line=>$show_tick_line,
		skip_first_tick => 0,
		skip_last_tick => 0,
		size=>8,
		side=>"left",
	);
	$axis->plot(parent=>$parent);
	
	my (@px,@py);
	foreach (sort {$a->[0] <=> $b->[0]} @$records)
	{
		my ($sta,$end,$val,$attrs) = @$_;
		my $y = nearest 0.01 , $data->{$chr}->{oy} + ($sta+$end)*$zoom/2;
		next if ($val > $max || $val < $min);
		my $dis = $axis->fetch_dis($val);
		my $x = $x1 < $x2 ? $x1 + $dis : $x1 - $dis;
		push @px , $x;
		push @py , $y;
	}
	
	# set the default color and stroke width
	my $color = defined $plot->{color} ? $plot->{color} : "000";
	$color = SBV::Colors::fetch_color($color);
	my $swidth = defined $plot->{stroke_width} ? $plot->{stroke_width} : 1;

	my $points = $parent->get_path(x=>\@px,y=>\@py,-type=>'polyline');
	$parent->polyline(%$points,fill=>'none',style=>"stroke:$color;stroke-width:$swidth");
}

sub _add_histogram_plot
{
	my ($data,$plot,$chr,$zoom,$parent) = @_;
	my $records = $plot->{data}->{$chr};

	# get the min and max value of the data
	my @vals = map { $$_[2] } @$records;
	my $min = defined $plot->{min} ? $plot->{min} : min(\@vals);
	my $max = defined $plot->{max} ? $plot->{max} : max(\@vals);
	my $tick = SBV::STAT::dividing($min,$max,-xtrue=>1);
	my $show_tick_label = $plot->{show_tick_label} || 0;
	my $show_tick_line = $plot->{show_tick_line} || 0;

	# create the x axis for val
	my $x1 = cal_x_coord($data,$chr,$plot->{loc0});
	my $x2 = cal_x_coord($data,$chr,$plot->{loc1});
	my $len = abs ($x1 - $x2);
	my $axis = SBV::STONE::AXIS->new(
		oy=>$data->{$chr}->{oy},ox=>$x1,length=>$len,
		tick=>$tick,
		show_tick_label=>$show_tick_label,
		show_tick_line=>$show_tick_line,
		skip_first_tick => 0,
		skip_last_tick => 0,
		size=>8,
		side=>"left",
	);
	$axis->plot(parent=>$parent);
	
	foreach (@$records)
	{
		my ($sta,$end,$val,$attrs) = @$_;
		next if ($val > $max || $val < $min);
		my $dis = $axis->fetch_dis($val);
		my $x = $x1 < $x2 ? $x1 : $x1 - $dis;
		my $y1 = nearest 0.01 , $data->{$chr}->{oy} + $sta*$zoom;
		my $y2 = nearest 0.01 , $data->{$chr}->{oy} + $end*$zoom;
		my $y = $y1 < $y2 ? $y1 : $y2;
		my $barH = abs($y2 - $y1);
		
		my $style = SBV::CONF::fetch_styles(%$attrs);
		$parent->rect(x=>$x,y=>$y,width=>$dis,height=>$barH,style=>$style);
	}

}

sub _add_heatmap_plot
{
	my ($data,$plot,$chr,$zoom,$parent) = @_;
	my $records = $plot->{data}->{$chr};
	
	# get the min and max value of the data
	my @vals = map { $$_[2] } @$records;
	my $min = defined $plot->{min} ? $plot->{min} : min(\@vals);
	my $max = defined $plot->{max} ? $plot->{max} : max(\@vals);
	my $tick = SBV::STAT::dividing($min,$max,-xtrue=>1);
	
	my @fills = SBV::CONF::fetch_val($plot,"fill");
	@fills = map { SBV::Colors::fetch_color($_) } @fills;
	if ($#fills == 0) 
	{
		unshift @fills , "#ffffff";
	} 
	
	# create the x axis for val
	my $x1 = cal_x_coord($data,$chr,$plot->{loc0});
	my $x2 = cal_x_coord($data,$chr,$plot->{loc1});
	my $len = abs ($x1 - $x2);
	my $x = $x1 < $x2 ? $x1 : $x2;
	
	foreach (@$records)
	{
		my ($sta,$end,$val,$attrs) = @$_;
		next if ($val > $max || $val < $min);

		# fetch y coord
		my $y1 = nearest 0.01 , $data->{$chr}->{oy} + $sta*$zoom;
		my $y2 = nearest 0.01 , $data->{$chr}->{oy} + $end*$zoom;
		my $y = $y1 < $y2 ? $y1 : $y2;
		my $barH = abs($y1-$y2);
		
		# get gradient color
		my $ratio = ($val - $min) / ($max - $min);
		my $index = int ($#fills * $ratio);
		my $fill = $#fills == 1 ? SBV::Colors::fetch_gradient_color($ratio,@fills) : $fills[$index];
		my $styles = SBV::CONF::fetch_styles(%$attrs,fill=>$fill);

		$parent->rect(x=>$x,y=>$y,width=>$len,height=>$barH,style=>$styles);
	}
	
}

sub _add_text_plot
{
	my ($data,$plot,$chr,$zoom,$parent) = @_;
	my $records = $plot->{data}->{$chr};

	my $flagy = 0;
	my $hi = $SBV::conf->{hspace};
	my $vi = $SBV::conf->{vspace};
	
	# fetch loc0 and loc1 coord
	my $x1 = cal_x_coord($data,$chr,$plot->{loc0});
	my $x2 = cal_x_coord($data,$chr,$plot->{loc1});
	my $thickness = $data->{$chr}->{x2} - $data->{$chr}->{x1};
	my $link_len = defined $plot->{'link_length'} ? $plot->{'link_length'} : 20;

	foreach (sort {$a->[0] <=> $b->[0] or $a->[1] <=> $b->[1]} @$records)
	{
		my ($sta,$end,$val,$attrs) = @$_;

		my $font = SBV::Font->new($attrs->{theme});
		my $font_style = $font->toStyle;
		my $textH = $font->fetch_text_height;
		my $textW = $font->fetch_text_width($val);
		my $texty;
		my $textx;
		
		my $y = nearest 0.01 , $data->{$chr}->{oy} + ($sta+$end)*$zoom/2;
		if ($y >= $flagy)
		{
			$texty = $y + $textH/2;
			$flagy = $y + $textH + $vi;
		}
		else 
		{
			$texty = $flagy + $textH/2;
			$flagy += $textH + $vi;
		}

		my $lineStyle;
		$lineStyle .= "stroke-width:$attrs->{link_thickness};" if (defined $attrs->{link_thickness});
		$lineStyle .= "stroke:$attrs->{link_color};" if (defined $attrs->{link_color});

		if ($attrs->{ideogram_highlights})
		{
			$parent->line(x1=>$data->{$chr}->{x1},x2=>$data->{$chr}->{x2},y1=>$y,y2=>$y,style=>$lineStyle);
		}
		
		if ($plot->{loc0} >= 0)
		{
			$textx = $x1 + $thickness + $link_len + $hi;
			$parent->line(x1=>$x1,x2=>$x1+$thickness,y1=>$y,y2=>$y,style=>$lineStyle) if ($plot->{show_links});
			$parent->line(x1=>$x1+$thickness,x2=>$x1+$thickness+$link_len,y1=>$y,y2=>$texty-$textH/2,style=>$lineStyle) if ($plot->{show_links});
		}
		else 
		{
			$textx = $x1 - $thickness - $link_len - $textW - $hi;
			$parent->line(x1=>$x1,x2=>$x1-$thickness,y1=>$y,y2=>$y,style=>$lineStyle) if ($plot->{show_links});
			$parent->line(x1=>$x1-$thickness,x2=>$x1-$thickness-$link_len,y1=>$y,y2=>$texty-$textH/2,style=>$lineStyle) if ($plot->{show_links});
		}
		
		$parent->text(x=>$textx,y=>$texty,style=>$font_style)->cdata($val);
	}
}

sub cal_x_coord
{
	my ($data,$chr,$loc) = @_;

	if ($loc < 0 )
	{
		return $data->{$chr}->{x1} + $loc;
	}
	else
	{
		return $data->{$chr}->{x2} + $loc;
	}
}