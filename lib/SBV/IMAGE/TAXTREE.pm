package SBV::IMAGE::TAXTREE;
#-------------------------------------------------+
#    [APM] This moudle was generated by amp.pl    |
#    [APM] Created time: 2014-12-19 17:27:39      |
#-------------------------------------------------+
=pod

=head1 Name

SBV::IMAGE::TAXTREE 

=head1 Synopsis

This module is not meant to be used directly

=head1 Feedback

Author: Peng Ai
Email:  aipeng0520@163.com

=head1 Version

Version history

=head2 v1.0

Date: 2014-12-19 17:27:39

=cut


use strict;
use warnings;
require Exporter;

use Math::Round;
use FindBin;
use lib "$FindBin::RealBin";
use lib "$FindBin::RealBin/lib";
use lib "$FindBin::RealBin/../";
use lib "$FindBin::RealBin/../lib";

use SBV::DEBUG;
use SBV::Colors;
use SBV::STAT qw/sum max min/;
use SBV::Constants;

sub new 
{
	my ($class,$file,$conf) = @_;
	my $treev = {};

	my $legend = {};
	my $tree = _load_tree($file,$conf);
	my $id_trans = _load_ids($tree);
	my $percent = _load_percent($conf);
	$treev->{tree} = $tree;
	$treev->{conf} = $conf;
	$treev->{id_trans} = $id_trans;
	$treev->{percent} = $percent;
	$treev->{legend} = $legend;
	bless $treev , $class;
	return $treev;
}

# load the tree file and set the outgroup
# if the outgroup is not exists witll use the default outgroup
sub _load_tree
{
	my ($file,$conf) = @_;
	my $format = $conf->{format};
	
	my $treeio = Bio::TreeIO->new('-format'=>$format,-file=>$file);
	my $tree = $treeio->next_tree;
	my @leaves = $tree->get_leaf_nodes;

	return $tree;
}

# load the id and internal id
sub _load_ids
{
	my $tree = shift;
	my @leaves = $tree->get_leaf_nodes;
	my $trans = {};

	foreach my$leaf (@leaves)
	{
		$trans->{$leaf->id} = $leaf;
	}

	return $trans;
}

# load the percent info 
sub _load_percent
{
	my $conf = shift;
	my $file = $conf->{percent} or return;

	$file = check_path($file);
	my $data = SBV::DATA::Frame->new($file,header=>1,rownames=>1);

	return $data;
}

sub plot
{
	my ($self,$parent) = @_;
	my $tree = $self->{tree};
	my $conf = $self->{conf};
	
	# set pie colors 
	my @samples = $self->{percent}->names;
	pop @samples;
	my @colors;
	if ($conf->{colors})
	{
		my $file = check_path($conf->{colors});
		my $color_data = SBV::DATA::Frame->new($file,rownames=>1);
		@colors = map { SBV::Colors::fetch_color($color_data->{row}->{$_}->[0]) } @samples;
	}
	else 
	{
		@colors = rainbow($#samples+1);
	}
	
	$self->{colors} = \@colors;
	$self->{samples} = \@samples;
	$self->legend(label=>\@samples,fill=>\@colors);

	# init legend
	my $legend;
	if ($conf->{legend})
	{
		my $lconf = SBV::CONF::fetch_first_conf('legend',$conf);
		my $legend_par = $self->legend;
		$legend = SBV::STONE::LEGEND->new(conf=>$lconf,%$legend_par);
		if ($lconf->{pos} eq "outright")
		{
			my $legend_width = $legend->width;
			$conf->{tw} -= $legend_width;
		}
	}

	SBV::DRAW::background($conf,$parent);
	my $group = $parent->group(id=>"tree$SBV::idnum");
	$SBV::idnum ++;

	if ($conf->{model} eq "normal")
	{
		&taxonomy_tree($self,$tree,$conf,$group);
	}
	elsif ($conf->{model} eq "circular")
	{
		&circular_taxonomy_tree($self,$tree,$conf,$group);
	}
	else  # default normal 
	{
		&taxonomy_tree($self,$tree,$conf,$group);
	}

	# add legend
	if ($conf->{legend})
	{
		$legend->location($conf);
		$legend->draw($parent);
	}
}

sub taxonomy_tree
{
	my ($self,$tree,$conf,$group) = @_;
	my %par;

	my $hi = $SBV::conf->{hspace};
	my $vi = $SBV::conf->{vspace};

	# load color and leaf labels definition files
	#my $defs = _load_defs($conf,$self->{id_trans});
	#my @datasets = _load_datasets($conf,$self->{id_trans});
	#my $axis_flag = 0;
	
	# set the width and height for the tree figure
	my $treeFW = $conf->{tw};
	my $treeFH = $conf->{th};
	my $x = $conf->{ox};
	my $y = $conf->{oty};

	my $rootNode = $tree->get_root_node;
	my $tail = $conf->{tail} || 0;
	ERROR("negative_length_err",$tail) if ($tail < 0);
	
	# pie radius 
	my $r = $conf->{radius} || 20;
	
	# now no dataset
	my $dataWidth = 0;

	my $treeL = $rootNode->height;
	my @leaves = $tree->get_leaf_nodes;
	my $unitH = nearest 0.001 , $treeFH/($#leaves + 1);
	
	my $min_best_unitH = $r*2.2*($#leaves+1);
	my $max_best_unitH = $r*2.8*($#leaves+1); 

	# warn if unit height is too large or to small 
	if ($unitH > $r*3)
	{
		WARN("The unit height is too large, [$unitH], best tree height(no margin) is in $min_best_unitH ~ $max_best_unitH");
	}
	elsif ($unitH < $r*2+$hi)
	{
		WARN("The unit height is too small, [$unitH], best tree height(no margin) is in $min_best_unitH ~ $max_best_unitH");
	}

	# leaf max width 
	my @ids = map {
		$_->id
	} @leaves;
	my $id_width = SBV::Font->fetch_font("leaf")->fetch_max_text_width(\@ids);
	
	#  root label width 
	my $rootID = $rootNode->id;
	$rootID =~ s/\d_//;
	my $root_width = SBV::Font->fetch_font("leaf")->fetch_text_width($rootID);
	
	# tree width 
	my $tree_width = $treeFW - $id_width - $root_width - $r*2 - $hi*2;
	ERROR("tree_width_err") if ($tree_width <= 0);

	my $unitL = $tree_width / $treeL;
	
	$par{colors} = $self->{colors};
	$par{unitH} = $unitH;
	$par{unitL} = $unitL;
	$par{idX} = $x + $tail + $tree_width + 2*$hi;
	$par{idW} = $id_width;
	$par{treeL} = $treeL;
	$par{parent} = $group;
	$par{conf} = $conf;
	$par{rootNode} = $rootNode;
	$par{treeY} = $y;
	$par{percent} = $self->{percent};

	my $py = _taxtree($rootNode,$x+$root_width+$r+$hi,$y+$unitH/2,\%par);
}

sub _taxtree
{
	my ($root,$ox,$oy,$par) = @_;

	my $unitL = $par->{unitL};
	my $unitH = $par->{unitH};
	my $parent = $par->{parent};
	my $conf = $par->{conf};

	my @nodes = $root->each_Descendent;
	
	my @py;
	my $py;
	my $tempy = $oy;
	foreach my$node(@nodes)
	{
		if ($node->is_Leaf)
		{
			_add_leaf($node,$ox,$tempy,$par);
			push @py , $tempy;
			$tempy += $unitH;
		}
		else 
		{
			my @subNodes = $node->get_all_Descendents;
			@subNodes  = grep { $_-> is_Leaf } @subNodes;
			$py = _taxtree($node,$ox+$unitL,$tempy,$par);
			push @py , $py;
			my $nodeH = $#subNodes * $unitH;
			$tempy += $nodeH + $unitH;
		}
	}
	
	$py = ($py[0] + $py[-1])/2;

	_add_clade($root,$par,$ox,@py);
	return $py;
}

sub _add_leaf
{
	my ($node,$x,$y,$par) = @_;
	
	my $unitL = $par->{unitL};
	my $parent = $par->{parent};
	my $conf = $par->{conf};
	my $r = $conf->{radius} || 20;
	my $percent = $par->{percent};
	
	# id
	my $label = $node->id;
	
	# draw branch line 
	my $x2 = $x + $unitL;
	$parent->line(x1=>$x,x2=>$x2,y1=>$y,y2=>$y,style=>"stroke:#000;stroke-width:2");
	
	# fetch the total percent
	my $true_id = fetch_true_id($node);
	my $value = nearest 0.001 , $percent->{row}->{$true_id}->[-1];
	$value =  $conf->{show_total_tags} ?  int ($value * $conf->{toatl_tags}) : "${value}%";

	# draw pie 
	_add_pie($par,$node,$x2,$y,$r) if ($percent);

	# draw label text 
	my $hi = $SBV::conf->{hspace};
	my $font = SBV::Font->fetch_font("leaf");
	my $textH = $font->fetch_text_height;
	my $textX = $x2 + $hi + $r;
	$label =~ s/^\d_//;
	
	my @str = ($label,"$value");
	SBV::DRAW::mtext(\@str,$textX,$y,parent=>$parent,xalign=>"right",yalign=>"center",class=>"leaf");
}

sub _add_clade
{
	my ($node,$par,$x,@py) = @_;
	
	my $py = ($py[0]+$py[-1])/2;
	my $unitL = $par->{unitL};
	my $parent = $par->{parent};
	my $conf = $par->{conf};
	my $r = $conf->{radius} || 20;
	my $percent = $par->{percent};
	
	my $label = $node->id;
	
	# draw branch line
	my $x1 = $node eq $par->{rootNode} ? $x : $x - $unitL;
	my $x2 = $x;
	$parent->line(x1=>$x1,x2=>$x2,y1=>$py,y2=>$py,style=>"stroke:#000;stroke-width:2");
	$parent->line(x1=>$x2,x2=>$x2,y1=>$py[0],y2=>$py[-1],style=>"stroke:#000;stroke-width:2") if ($#py >= 1);
	
	# fetch the total percent
	my $true_id = fetch_true_id($node);
	my $value = nearest 0.001 , $percent->{row}->{$true_id}->[-1] || 0;
	
	# draw pie 
	_add_pie($par,$node,$x2,$py,$r) if ($percent && !$conf->{hide_pie});

	# draw label 
	my $depth = $node->height;

	my $hi = $SBV::conf->{hspace};
	my $vi = $SBV::conf->{vspace};
	
	my $font = SBV::Font->fetch_font("leaf");
	$label =~ s/^\d_//;
	
	my @str = ($label,"$value%");
	my $label_width = $font->fetch_max_text_width(\@str);
	my $textH = $font->fetch_text_height;
	
	my $textX = $x - $label_width - $r - $hi;
	my $textY = $py - $vi;

	if ($node eq $par->{rootNode})
	{
		$textX = $x - $label_width - $hi;
		$textY = $py + $textH/2;
		
		if ($value == 0)
		{
			$parent->text(x=>$textX,y=>$textY,class=>"leaf")->cdata($label);
			return;
		}
	}
	elsif ($label_width+$hi+2*$r > $unitL)
	{
		$textX = $x - $hi - $label_width;
		$textY = $py - $r - $vi + $textH ;
	}
	
	SBV::DRAW::mtext(\@str,$textX,$textY,parent=>$parent,xalign=>"right",yalign=>"bottom",class=>"leaf");
}

sub _add_pie
{
	my ($par,$node,$cx,$cy,$r) = @_;

	my $conf = $par->{conf};
	my $parent = $par->{parent};
	my $percent = $par->{percent};
	
	my $id = fetch_true_id($node);
	my $value = $percent->{row}->{$id};
	
	return unless $#$value > -1;
	
	my @values = @$value;
	
	my $totals = $percent->{col}->{"total_percent"};
	my $min = min($totals);
	my $max = max($totals);
	my $val = pop @values;
	my $ratio = ($val-$min)/($max-$min);
	$r = (0.5+0.5*$ratio)*$r;

	my $num = scalar @values;
	my $colors = $par->{colors};
	my @colors = @$colors;
	my $sum = sum(\@values);
	my $temp = 0;
	foreach (@values)
	{
		my $color = shift @colors;
		my $angle = $_*360/$sum;

		if ($angle >= 360)
		{
			$parent->circle(cx=>$cx,cy=>$cy,r=>$r,class=>'pie',style=>"fill:$color;stroke-width:0");
		}
		else 
		{
			my %fan = (start=>$temp,color=>$color,r1=>0,class=>'pie',raise=>0,parent=>$parent);
			SBV::DRAW::Fan($cx,$cy,360,$temp+$angle,$r,%fan);
		}
		
		$temp += $angle;
	}
	
	$parent->circle(cx=>$cx,cy=>$cy,r=>$r,style=>"fill:none;stroke:#000000;stroke-width:1");

	return $r;
}

sub circular_taxonomy_tree
{
	my ($self,$tree,$conf,$group) = @_;
	my %par;

	my $hi = $SBV::conf->{hspace};
	my $vi = $SBV::conf->{vspace};

	# load color and leaf labels definition files
	#my $defs = _load_defs($conf,$self->{id_trans});
	#my @datasets = _load_datasets($conf,$self->{id_trans});
	#my $axis_flag = 0;
	
	# set the width and height for the tree figure
	my $treeFW = $conf->{tw};
	my $treeFH = $conf->{th};
	my $x = $conf->{ox};
	my $y = $conf->{oty};

	my $rootNode = $tree->get_root_node;
	my $tail = $conf->{tail} || 0;
	ERROR("negative_length_err",$tail) if ($tail < 0);
	
	# no datasets 
	my $dataWidth = 0;
	
	my $treeL = $rootNode->height;

	# set the unit angle
	my @leaves = $tree->get_leaf_nodes;
	my @ids = map { $_->id } @leaves;
	my $unitA = $conf->{angle} / ($#leaves + 1);

	# set the radius and circle origin points coord
	my $or = $conf->{start_radius};
	my $R = $conf->{tw} > $conf->{th} ? $conf->{th} : $conf->{tw};
	my $r = $R/2;
	my $cx = $x + $conf->{tw}/2;
	my $cy = $y + $conf->{th}/2;
	
	# set the unit length
	my $id_width = SBV::Font->fetch_font("leaf")->fetch_max_text_width(\@ids);
	my $tree_width = $r - $or - $id_width - $tail - 2*$hi - $dataWidth;
	my $unitL = $tree_width / $treeL;

	# rotate the group
	if (my $rotation = $conf->{rotation})
	{
		$rotation = $rotation * 360 / $TWOPI;
		$group->setAttribute("transform","rotate($rotation,$cx,$cy)");
	}
	
	# creat new plolar coord system for circular tree 
	my $polar = SBV::Coordinate::POLAR->new($cx,$cy,parent=>$group);
	
	# set the par 
	$par{colors} = $self->{colors};
	$par{unitA} = $unitA;
	$par{unitL} = $unitL;
	$par{idR} = $or + $tail + $tree_width + $hi;
	$par{idW} = $id_width;
	$par{treeL} = $treeL;
	$par{parent} = $group;
	$par{conf} = $conf;
	$par{rootNode} = $rootNode;
	$par{cx} = $cx;
	$par{cy} = $cy;
	$par{r} = $r;
	$par{polar} = $polar;
	$par{percent} = $self->{percent};

	# the main part 
	_circular_taxtree($rootNode,$or+$tail,0,\%par);
}

sub _circular_taxtree
{
	my ($root,$r,$a,$par) = @_;

	my $unitL = $par->{unitL};
	my $unitA = $par->{unitA};
	my $polar = $par->{polar};
	my $parent = $par->{parent};
	my $conf = $par->{conf};

	my @nodes = $root->each_Descendent;
	
	my @pa;
	my ($pa,$amin,$amax,$tempa);
	$tempa = $a;
	foreach my$node(@nodes)
	{
		if ($node->is_Leaf)
		{
			_add_circular_leaf($node,$r,$tempa,$par);
			push @pa , $tempa;
			$tempa += $unitA;
		}
		else 
		{
			my @subNodes = $node->get_all_Descendents;
			@subNodes  = grep { $_-> is_Leaf } @subNodes;
			$pa = _circular_taxtree($node,$r+$unitL,$tempa,$par);
			push @pa , $pa;
			my $nodeA = $#subNodes * $unitA;
			$tempa += $nodeA + $unitA;
		}
	}
	
	$pa = ($pa[0] + $pa[-1])/2;

	_add_circular_clade($root,$par,$r,@pa);
	return $pa;
}

sub _add_circular_leaf
{
	my ($node,$r,$a,$par) = @_;
	
	my $polar = $par->{polar};
	my $unitL = $par->{unitL};
	my $unitA = $par->{unitA};
	my $percent = $par->{percent};
	my $conf = $par->{conf};
	my $pie_r = $conf->{radius} || 20;
	my $hi = $SBV::conf->{hspace};

	# id 
	my $label = $node->id;

	# draw branch line 
	my $r2 = $r+$unitL;
	my $leafLine = $polar->line($r,$a,$r2,$a,class=>"leaf",style=>"stroke:#000;stroke-width:2");

	# fetch the total percent
	my $true_id = fetch_true_id($node);
	my $value = nearest 0.001 , $percent->{row}->{$true_id}->[-1];

	# draw pie 
	my ($x,$y) = $polar->polar2pos($r2,$a,"angle");
	my $true_pie_r = _add_pie($par,$node,$x,$y,$pie_r) if ($percent);
	
	# add label
	my $font = SBV::Font->fetch_font("leaf");
	my $theme = $font->toStyle();
	$label =~ s/^\d_//;
	
	my @str = ($label,"$value%");
	my $label_width = $font->fetch_max_text_width(\@str);
	my $textH = $font->fetch_text_height;
	my $textr = $r2 + $true_pie_r + $hi;
	$polar->text($textr,$a,-$hi/2,$label,theme=>$theme);
	$polar->text($textr,$a,+$textH+$hi/2,"$value%",theme=>$theme);
}

sub _add_circular_clade
{
	my ($node,$par,$r,@pa) = @_;

	my $polar = $par->{polar};
	my $unitL = $par->{unitL};
	my $unitA = $par->{unitA};
	my $percent = $par->{percent};
	my $conf = $par->{conf};
	my $pie_r = $par->{radius} || 20;
	my $hi = $SBV::conf->{hspace};
	
	# label / id 
	my $label = $node->id;
	
	# add branch line 
	my $pa = ($pa[0] + $pa[-1])/2;
	my $r2 = $node eq $par->{rootNode} ? $r : $r - $unitL;
	$polar->line($r,$pa,$r2,$pa,class=>"clade",style=>"stroke:#000;stroke-width:2");
	$polar->arc($r,$pa[0],$pa[-1],class=>"clade",style=>"stroke:#000;stroke-width:2");

	# fetch the total percent
	my $true_id = fetch_true_id($node);
	my $value = nearest 0.001 , $percent->{row}->{$true_id}->[-1] || 0;
	
	# draw pie 
	my ($x,$y) = $polar->polar2pos($r,$pa,"angle");
	my $true_pie_r = _add_pie($par,$node,$x,$y,$pie_r) if ($percent);
	
	# add label 
	my $font = SBV::Font->fetch_font("leaf");
	my $theme = $font->toStyle();
	$label =~ s/^\d_//;
	
	my @str = ($label,"$value%");
	my $label_width = $font->fetch_max_text_width(\@str);
	my $textH = $font->fetch_text_height;
	
	my $trans = -$hi;
	my $textr;
	if ($node eq $par->{rootNode})
	{
		return;
	}
	elsif ($r - $true_pie_r - $pie_r - $label_width > $r2)
	{
		$textr = $r - $true_pie_r - $label_width;
	}
	else 
	{
		$textr = $r - $label_width - $hi;
		$trans = -$true_pie_r - $hi;
	}
	
	$polar->text($textr,$pa,-$hi-$textH+$trans,$label,theme=>$theme);
	
	if ($pa > 180)
	{
		$textr += $label_width - $font->fetch_text_width("$value%");
	}

	$polar->text($textr,$pa,$trans,"$value%",theme=>$theme);
}

sub fetch_true_id
{
	my $node = shift;

	my $id = $node->id;
	my $layer = $1 if ($id =~ /^(\d)_/);
	
	if ($layer > 1)
	{
		my $ancestor = $node->ancestor;
		$id = $ancestor->id . ";" . $id;
	}

	return $id;
}

sub legend
{
	my $self = shift;
	my $legend = $self->{legend};
	
	if (@_)
	{
		my %par = @_;
		$legend->{$_} = $par{$_} foreach (keys %par);
	}
	else 
	{
		return $legend;
	}

	return 1;
}
