package SBV::IMAGE::SDU;
#------------------------------------------------+
#    [APM] This moudle is generated by amp.pl    |
#    [APM] Created time: 2014-02-20 11:19:32     |
#------------------------------------------------+
=pod

=head1 Name

SBV::IMAGE::SDU -- a module to draw sequence dress image 

=head1 Synopsis

This module is not meant to be used directly

=head1 Feedback

Author: Peng Ai
Email:  aipeng0520@163.com

=head1 Version

Version history

=head2 v1.0

Date: 2014-02-20 11:19:32

=cut


use strict;
use warnings;
require Exporter;

use Math::Cephes qw/ceil/;

use FindBin;
use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/lib";
use lib "$FindBin::RealBin/../";
use lib "$FindBin::RealBin/../lib";

use SBV::STAT;
use SBV::STONE::AXIS;
use SBV::DEBUG;

sub new 
{
	my ($class,$data,$conf) = @_;

	my $object = {};
	$object->{data} = $data;
	$object->{conf} = $conf;
	
	bless $object , $class;

	return $object;
}

sub plot
{
	my ($self,$parent,%opts) = @_;
	my $conf = $self->{conf};
	my $data = $self->{data};
	$self->{parent} = $parent;

	SBV::DRAW::background($conf,$parent);
	my $group = $parent->group(id=>"sdu$SBV::idnum");
	$SBV::idnum ++;
	$self->{group} = $group;
	
	my @decorates = parse_decorates($conf);

	my $ox = $conf->{ox};
	my $oy = $conf->{oty};
	my $hspace = $SBV::conf->{hspace};
	my $vspace = $SBV::conf->{vspace};
	my $y = $oy;
		
	my $font = SBV::Font->new($conf->{theme});
	my $pos_font = SBV::Font->new(); # 
	my $labelH = $font->fetch_text_height;
	my $seqstr = $data->{seq};

	my $elbn = $conf->{num}; # each line base num
	my $ebbn = $conf->{subnum}; # each block base num
	$ebbn = $elbn if ($ebbn > $elbn || $ebbn == 0);
	my $line_spacing = $conf->{line_spacing};

	# fetch sum line num
	my $sln = ceil($data->{length} / $elbn); # sum line num
	
	# split sequence to lines with blocks
	my ($dseqstr,@dstyles) = parse_decorate_seq($data->{length},@decorates);

	my @seq =  map { s/(\w{$ebbn})/$1 /g; chop $_ if (/\s$/); $_ } 
		map { substr($seqstr,$_*$elbn,$elbn); } 0 .. $sln - 1;
	
	# fetch the size of the sequence text
	my $seq_height = $labelH * $sln + $line_spacing * ($sln - 1);
	my $seq_width = $font->fetch_text_width($seq[0]);
	
	my $max_pos = ($sln - 1)*$elbn + 1;
	my $pos_label_width = $pos_font->fetch_text_width($max_pos);
	
#-------------------------------------------------------------------------------
# draw header
#-------------------------------------------------------------------------------
	unless ($conf->{nohead})
	{
		my $header = $group->group(class=>"sdu_header");
		
		# add sequence description
		my $font = SBV::Font->new($conf->{label_theme});
		my $labelH = $font->fetch_text_height;
		$y += $labelH;
		$header->text(x=>$ox,y=>$y,style=>$font->toStyle)->cdata("name: $data->{name}");
		$y += $labelH + $vspace;
		$header->text(x=>$ox,y=>$y,style=>$font->toStyle)->cdata("length: $data->{length}");
		
		# add sequence bar
		$y += 2*$vspace;
		$header->rect(x=>$ox,y=>$y,width=>$pos_label_width+$seq_width,height=>$conf->{thickness},
			style=>"fill:$conf->{header_color};stroke-width:1;stroke:#000");
		
		# add axis
		$y += $conf->{thickness};
		my $scale = dividing(1,$data->{length},-xtrue=>1);
		my $axis = SBV::STONE::AXIS->new(ox=>$ox,oy=>$y,length=>$pos_label_width+$seq_width,
			parent=>$header,tick=>$scale,side=>"right",start=>0,translate=>0,skip_first_tick=>0);
		$axis->plot;
		
		# add decorates
		foreach (sort {$a->[0]<=>$b->[0]} grep {$_->[2]->{type} eq "symbol"} @decorates)
		{
			my ($sta,$end,$attrs) = @$_;
			ERROR('seq_length_overflow)') if ($end > $data->{length});
			next if ($attrs->{color} eq "none" );

			$sta = 0 if (1 == $sta);
			my $dx = $axis->fetch_coord($sta); # decorate x 
			my $dw = $axis->fetch_coord($end)-$axis->fetch_coord($sta); # decorate width
			my $symid = SBV::STONE::SYMBOL::new($attrs->{shape},width=>$dw,height=>$conf->{thickness},
				fill=>$attrs->{fill},color=>$attrs->{color},stroke_width=>$attrs->{stroke_width});
			$header->group()->use(x=>$dx,y=>$y-$conf->{thickness},width=>$dw,height=>$conf->{thickness},'-href'=>"#$symid");
		}

		$y += $conf->{spacing};
	}
	
#-------------------------------------------------------------------------------
# draw sequence 
#-------------------------------------------------------------------------------
	my $textx = $ox + $pos_label_width + $hspace;
	my $texty = $y + $seq_height; 
	my $seq = $group->group(class=>"seq"); # default sequence font 
	my $unit_seq_w = $font->fetch_text_width('A');
	my $unit_seq_len = length $seq[0];

	# draw sequence label highlights
	foreach (sort {$a->[0]<=>$b->[0]} grep {$_->[2]->{type} eq "highlight"} @decorates)
	{
		my ($sta,$end,$attrs) = @$_;
		ERROR('seq_length_overflow)') if ($end > $data->{length});
		
		my ($row1,$col1) = fetch_pos($sta,$elbn,$ebbn);
		my ($row2,$col2) = fetch_pos($end,$elbn,$ebbn);

		if (0 == $row2 - $row1)
		{	
			my $hl_x = $textx + $unit_seq_w * ($col1-1);
			my $hl_y = $y + ($labelH+$line_spacing) * ($row2-1);
			my $hl_w = $unit_seq_w * ($col2-$col1+1);
			$seq->rect(x=>$hl_x,y=>$hl_y,width=>$hl_w,height=>$labelH,
				style=>SBV::CONF::fetch_styles(%$attrs));
		}
		elsif (1 == $row2 - $row1)
		{
			my $hl_x = $textx + $unit_seq_w * ($col1-1);
			my $hl_y = $y + ($labelH+$line_spacing) * ($row1-1);
			my $hl_w = $unit_seq_w * ($unit_seq_len-$col1+1);
			$seq->rect(x=>$hl_x,y=>$hl_y,width=>$hl_w,height=>$labelH,
				style=>SBV::CONF::fetch_styles(%$attrs));

			$hl_x = $textx;
			$hl_y = $y + ($labelH+$line_spacing) * ($row2-1);
			$hl_w = $unit_seq_w * ($col2);
			$seq->rect(x=>$hl_x,y=>$hl_y,width=>$hl_w,height=>$labelH,
				style=>SBV::CONF::fetch_styles(%$attrs));
		}
		else
		{
			my $hl_x = $textx + $unit_seq_w * ($col1-1);
			my $hl_y = $y + ($labelH+$line_spacing) * ($row1-1);
			my $hl_w = $unit_seq_w * ($unit_seq_len-$col1+1);
			$seq->rect(x=>$hl_x,y=>$hl_y,width=>$hl_w,height=>$labelH,
				style=>SBV::CONF::fetch_styles(%$attrs));
			
			for ($row1+1 .. $row2-1)
			{
				$hl_x = $textx;
				$hl_y = $y + ($labelH+$line_spacing) * ($_-1);
				$hl_w = $unit_seq_w * $unit_seq_len;
				$seq->rect(x=>$hl_x,y=>$hl_y,width=>$hl_w,height=>$labelH,
					style=>SBV::CONF::fetch_styles(%$attrs));
			}

			$hl_x = $textx;
			$hl_y = $y + ($labelH+$line_spacing) * ($row2-1);
			$hl_w = $unit_seq_w * ($col2);
			$seq->rect(x=>$hl_x,y=>$hl_y,width=>$hl_w,height=>$labelH,
				style=>SBV::CONF::fetch_styles(%$attrs));
		}
	}
	
	# draw label
	my $seq_text = $seq->text(x=>$textx,y=>$texty,style=>$font->toStyle);
	my $pos_text = $seq->text(x=>$ox,y=>$texty,style=>$pos_font->toStyle);
	for (my$i=0;$i<$sln;$i++)
	{
		$y += $labelH;

		# draw position label
		my $pos_label = $i * $elbn + 1;
		my $pos_label_x = $ox + $pos_label_width - $pos_font->fetch_text_width($pos_label);
		$pos_text->tspan(x=>$pos_label_x,y=>$y)->cdata($pos_label);

		my @array = dseq_to_pos( substr($dseqstr,$pos_label-1,$elbn) ,$ebbn );
		
		foreach (@array)
		{
			my ($sta,$len,$flag) = @$_;	
			
			# the label 
			my $cdata = substr($seq[$i],$sta,$len);
			
			# the label start pos
			my $tspanx = $textx + $unit_seq_w * $sta; 
			
			# tspan attributes
			my %opts = (x=>$tspanx,y=>$y);
			my $attrs = $dstyles[$flag-1];
			
			# the font size and family is fixed
			my $d_font = $attrs->{theme} ? SBV::Font->new($attrs->{theme}) : $font;
			$d_font->{'font-family'} = $font->{'font-family'};
			$d_font->{'font-size'} = $font->{'font-size'};

			my $style = $d_font->toStyle;
			$opts{style} = $style if (0 != $flag);
			$seq_text->tspan(%opts)->cdata($cdata);
			
			if ($attrs->{underline} && $flag != 0)
			{
				my $x2 = $tspanx + $unit_seq_w * $len;
				$seq->line(x1=>$tspanx,x2=>$x2,y1=>$y+2,y2=>$y+2,style=>"stroke-width:1;stroke:$d_font->{fill}");
			}
		}

		$y += $line_spacing;
	}
	
	# resize the image 
	unless ($conf->{fix_size})
	{
		my $width = $pos_label_width+$seq_width;

		my $margin = SBV::CONF::fetch_margin($conf);
		$y += $margin->{bottom};
		$width += $margin->{left} + $margin->{right};
		$margin = SBV::CONF::fetch_margin();
		$y += $margin->{bottom};
		$width += $margin->{left} + $margin->{right};

		my $bg = $SBV::conf->{background} ? 1 : 0;
		SBV::DRAW::resize(width=>$width,height=>$y,bg=>$bg);
	}
}

sub parse_decorates
{
	my $conf = shift;
	return () unless $conf->{decorates};
	$conf = SBV::CONF::fetch_first_conf("decorates",$conf);
	return () unless $conf->{decorate};
	
	my @decorates = ();
	if (ref $conf->{decorate} eq "ARRAY")
	{
		foreach my$subconf(@{$conf->{decorate}})
		{
			_parse_decorate(\@decorates,$conf,$subconf);
		}
	}
	elsif (ref $conf->{decorate} eq "HASH")
	{
		_parse_decorate(\@decorates,$conf,$conf->{decorate});	
	}

	return @decorates;
}

sub _parse_decorate
{
	my ($decorates,$conf,$subconf) = @_;
	return unless $subconf->{file};
	my $file = check_path($subconf->{file});

	# inherit attr from ticks
	foreach my$key (keys %$conf)
	{
		next if ($key eq "decorate");
		$conf->{$key} = SBV::Colors::fetch_color($conf->{$key}) if ($key eq "color" || $key eq "fill" || $key eq "header_color");
		$subconf->{$key} = $conf->{$key} unless $subconf->{$key};
	}

	# read decorate file 
	open FH,$file or die "can't open file $file $!";
	while(<FH>)
	{
		chomp;
		next if (/^#/);
		next if ($_ eq "");

		my ($sta,$end,$attrs) = split;
		($sta,$end) = ($end,$sta) if ($sta > $end);
		
		my $attrs_hash = {};
		
		foreach my$name(keys %$subconf)
		{
			$attrs_hash->{$name} = $subconf->{$name} unless ($name eq "file");	
		}

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
		
		push @$decorates , [$sta,$end,$attrs_hash];
	}
	close FH;
}

sub parse_decorate_seq
{
	my ($len,@decorates) = @_;

	my $raw = '0' x $len;
	my @seq = split // , $raw;
	my @styles;

	my $tag = 1;
	foreach (sort {$a->[0]<=>$b->[0]} grep {$_->[2]->{type} eq "style"} @decorates)
	{
		my ($dsta,$dend,$attrs) = @$_;
		ERROR('seq_length_overflow)') if ($dend > $len);
	
		for ($dsta .. $dend)
		{
			$seq[$_ - 1]  = $tag;	
		}
		
		$tag ++;
		push @styles , $attrs;
	}

	my $new = join "" , @seq;
	
	return ($new,@styles);
}

sub fetch_pos
{
	my ($pos,$elbn,$ebbn) = @_;
	my $row = ceil($pos/$elbn);
	my $col = $pos % $elbn;
	
	$col = $elbn if ($col == 0);
	$col += ceil($col/$ebbn) - 1;
	
	return ($row,$col);
}

# turn dseq info to position info
sub dseq_to_pos
{
	my ($dseq,$ebbn) = @_;
	my @pos;
	
	my @array = split // , $dseq;
	my $flag = $array[0];
	
	my $sta = 0;
	my $len = 0;
	for (my$i=0;$i<@array;$i++)
	{
		if ($array[$i] eq "$flag")
		{
			$len ++;
		}
		else
		{
			$sta += ceil(($sta+1)/$ebbn) - 1;
			$len += ceil($len/$ebbn) - 1;
			push @pos , [$sta,$len,$flag];
			$sta = $i;
			$len = 1;
			$flag = $array[$i];
		}
	}

	$sta += ceil(($sta+1)/$ebbn) - 1;
	$len += ceil($len/$ebbn) - 1;
	push @pos , [$sta,$len,$flag];
	
	return @pos;
}