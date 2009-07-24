#
# File: OP/SeriesChart.pm
#
# Copyright (c) 2009 TiVo Inc.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Common Public License v1.0
# which accompanies this distribution, and is available at
# http://opensource.org/licenses/cpl1.0.txt
#
use strict;
use warnings;

use OP;

use OP::Enum::Inter;

use Image::Magick;
use Time::HiRes;

create "OP::SeriesChart" => {
  name => OP::Name->assert(
    ::optional(),
  ),

  yMin => OP::Int->assert(
    ::optional(),
  ),

  yMax => OP::Int->assert(
    ::optional(),
  ),

  width => OP::Int->assert(
    ::default(320),
  ),

  height => OP::Int->assert(
    ::default(240),
  ),

  colors => OP::Array->assert(
    OP::Array->assert(
      OP::Int->assert(
        ::min(0),
        ::max(255),
      ),
      ::size(3),
    ),
    ::default(
      # Neat site
      # http://www.personal.psu.edu/cab38/ColorBrewer/ColorBrewer.html

      # green
      [ 35, 200, 69 ],
      # orange
      [ 250, 92, 1 ],
      # red
      [ 250, 24, 29 ],
      # gray
      [ 150, 150, 150 ],
      # pink
      [ 250, 64, 126 ],
      # lavender i guess
      [ 106, 81, 163 ],
      # blue
      [ 33, 113, 181 ],
    ),
  ),

  font => OP::Str->assert(
    default('/usr/share/X11/fonts/TTF/luxisb.ttf'),
  ),

  bgColor => OP::Array->assert(
    OP::Float->assert(min(0), max(255)),
    default([ 255, 255, 255, 1 ]),
    size(4)
  ),

  gridColor => OP::Array->assert(
    OP::Float->assert(min(0), max(255)),
    default([ 200, 200, 200, .5 ]),
    size(4)
  ),

  unitColor => OP::Array->assert(
    OP::Float->assert(min(0), max(255)),
    default([ 0,0,0,1 ]),
    size(4)
  ),

  stacked => OP::Int->assert(
    true, false,
    ::default(true),
  ),

  addSeries => sub($$) {
    my $self = shift;
    my $series = shift;

    $self->{_series} ||= OP::Array->new();
    $self->{_xMins}  ||= OP::Array->new();
    $self->{_xMaxes} ||= OP::Array->new();
    $self->{_yMins}  ||= OP::Array->new();
    $self->{_yMeds}  ||= OP::Array->new();
    $self->{_yMaxes} ||= OP::Array->new();

    my $data = $series->cooked();

    my $keys = $data->keys();
    my $values = $data->values();

    $self->{_series}->push($series);
    $self->{_xMins}->push($keys->min());
    $self->{_xMaxes}->push($keys->max());
    $self->{_yMins}->push($values->min());
    $self->{_yMeds}->push($values->median());
    $self->{_yMaxes}->push($values->max());
  },

  xMin => sub($) {
    my $self = shift;

    return if !$self->{_xMins};

    return $self->{_xMins}->min();
  },

  xMax => sub($) {
    my $self = shift;

    return if !$self->{_xMaxes};

    return $self->{_xMaxes}->max();
  },

  _yMin => sub($) {
    my $self = shift;

    return if !$self->{_yMins};

    return defined($self->{yMin})
      ? $self->{yMin}
      : $self->{_yMins}->min();
  },

  _yMed => sub($) {
    my $self = shift;

    return if !$self->{_yMeds};

    return $self->{_yMeds}->median();
  },

  _yMax => sub($) {
    my $self = shift;

    my $yMax;
    if ( $self->{yMax} ) {
      $yMax = $self->{yMax}
    } else {
      if ( $self->stacked() ) {
        $yMax = $self->{_yMaxes}->sum() * .85;
      } else {
        $yMax = $self->{_yMaxes}->max();
      }
    }

    return $yMax;
  },

  xValueToCoord => sub($$) {
    my $self = shift;
    my $x = shift;

    my $xFloor  = $self->xMin();
    my $xCeil   = $self->xMax();

    my $yFloor = $self->xcFloor();
    my $yCeil = $self->width()-1;

    if ( $xCeil - $xFloor == 0 ) {
      die "Insufficient datapoints to complete series";
    }

    return $self->xcFloor()
      # + ( int(($yFloor+($yCeil-$yFloor))
      + ( int(($yCeil-$yFloor)
      * ($x-$xFloor)/($xCeil-$xFloor)) );
  },

  yValueToCoord => sub($$) {
    my $self = shift;
    my $y = shift;

    my $xFloor  = $self->_yMin();
    my $xCeil   = $self->_yMax();

    my $yFloor = 0;
    my $yCeil = $self->ycCeil();

    if ( $xCeil - $xFloor == 0 ) {
      die "XMaxes Size ". $self->{_xMaxes}->size()
        ." Ceil $xCeil - Floor $xFloor == 0 (weird)";
    }

    return $yCeil - int(($yFloor+($yCeil-$yFloor))
      * ($y-$xFloor)/($xCeil-$xFloor));
  },

  yCoordToValue => sub($$) {
    my $self = shift;
    my $y = shift;

    my $xFloor = 0;
    my $xCeil = $self->ycCeil();

    my $yFloor  = $self->_yMin();
    my $yCeil   = $self->_yMax();

    return sprintf('%.01f',
      $yCeil - (($yCeil-$yFloor) * ($y-$xFloor)/($xCeil-$xFloor))
    );
  },

  ycCeil => sub($) {
    my $self = shift;

    # return $self->height()-25;
    return $self->height()-1;
  },

  xcFloor => sub($) {
    my $self = shift;

    # return 15;
    return 0;
  },

  render => sub($) {
    my $self = shift;

    return undef if !$self->{_series};

    if ( !$self->{_image} ) {
      my $image = Image::Magick->new(
        magick => 'png'
      );

      $image->Set(size=> join("x", $self->width(), $self->height()));
   
      $image->ReadImage(sprintf('xc:rgba(%s)',$self->bgColor()->join(',')));

      $self->{_image} = $image;
    }

    #
    # Stack-based fun:
    #
    # Polygons need to be painted in reverse order, but before text
    # and markers.
    #
    # To take care of this, anonymous sub{ } blocks which render the
    # chart elements are unshifted or pushed onto a stack. The subs in the
    # stack run in sequence, after in-memory series stacking operations
    # are complete.
    #
    # Any sub{ } blocks added to a stack *must* be shifted or popped off,
    # or massive memory leaks will result.
    #
    my $lineStack  = OP::Array->new();
    my $shapeStack = OP::Array->new();
    my $labelStack = OP::Array->new();

    my $base = { };
    my $prev = { };
    my $xTicks = OP::Hash->new();

    $self->{_series}->each( sub {
      my $series = shift;

      my $color = $self->colors()->shift();
      $self->colors()->push($color);

      my $data = $series->cooked();
      my $keys = $data->keys();

      my $lastXC;
      my $lastY;
      my $lastYC;

      my $firstYC;

      my $minY;
      my $minYX;

      my $maxY;
      my $maxYX;

      my $points = $keys->collect(sub {
        my $x = shift;
        my $y = $data->{$x};
        my $rawY = $y;

        if ( !defined($minY) || $y < $minY ) {
          $minY = $y;
          $minYX = $x;
        }

        if ( !defined($maxY) || $y > $maxY ) {
          $maxY = $y;
          $maxYX = $x;
        }

        my $baseY = 0;

        if ( $self->stacked() ) {
          for ( @{ $self->{_series} } ) {
            last if $_ == $series;

            $baseY += $_->yForX($x);
          }
        }

        $y += $baseY;

        my ($xc, $yc) = ($self->xValueToCoord($x), $self->yValueToCoord($y));

        $prev->{$xc} = $self->ycCeil() if !defined $prev->{$xc};

        my $baseYC = $self->yValueToCoord($baseY);
        $firstYC = $yc if !defined $firstYC;

        my $offset = $self->stacked()
          # ? ( $prev->{$xc} - $yc ) * .2
          ? ( $baseYC - $yc ) * .2
          : ( ( $self->ycCeil() - $yc ) * .075 );

        $offset = 0.1 if $offset <= 0.1;

        if (
          ( $series->yInterpolate() == OP::Enum::Inter::Constant )
            && $rawY == $lastY
        ) {
          $lastY = $rawY;
          $lastYC = $yc;

          return();
	}

        my $xNudge = 0;

        if ( $series->yInterpolate() == OP::Enum::Inter::Constant ) {
          if ( $xc == $self->xcFloor() ) {
            if ( $keys->size() > 1 ) {
              my $next;

              for my $key ( @$keys ) {
                $next = $key;
                last if $data->{$key} != $rawY;
              }

              $xNudge = ( $self->xValueToCoord($next) - $xc ) / 2;
            } else {
              $xNudge = ( $self->width() - 1 - $xc ) / 2;
            }
          } else {
            $xNudge = ( $xc - $lastXC ) / 2;
          }
        }

        $xTicks->{$xc} = $x;

        $lastXC = $xc;
        $prev->{$xc} = $yc;

        my $pointset = OP::Array->new();

        if (
          defined $lastYC
            && $series->yInterpolate() == OP::Enum::Inter::Constant
        ) {
          $pointset->push( join(",", $xc, $lastYC) );
        }

        $pointset->push( join(",", $xc, $yc) );

        $lastY = $rawY;
        $lastYC = $yc;

        OP::Array::yield(@$pointset);
      } );

      $points->unshift( sprintf('%i,%i',$self->xcFloor(),$firstYC) );
      $points->unshift( sprintf('%i,%i',$self->xcFloor(),$self->ycCeil()) );
      $points->push( sprintf('%i,%i',$self->width()-1,$lastYC));
      $points->push( sprintf('%i,%i',$self->width()-1,$self->ycCeil()) );

      my $stroke = sprintf('rgba(%s)', join(',',@$color,1));

      $lineStack->unshift( sub {
        {
          my $err = $self->{_image}->Draw(
            primitive => 'polygon',
            points => $points->join(" "),
            fill => sprintf('rgba(%s)', $self->bgColor()->join(',')),
            stroke => "none",
          );

          die $err if $err;
        }

        my $err = $self->{_image}->Draw(
          primitive => 'polygon',
          points => $points->join(" "),
          fill => sprintf('rgba(%s)', join(',',@$color,.125)),
          stroke => $stroke
        );

        die $err if $err;
      } );

      $labelStack->push( sub {
        my $minBaseY = 0;
        my $maxBaseY = 0;

        if ( $self->stacked() ) {
          for ( @{ $self->{_series} } ) {
            last if $_ == $series;

            $minBaseY += $_->yForX($minYX);
            $maxBaseY += $_->yForX($maxYX);
          }
        }

        my $minYXC = $self->xValueToCoord($minYX);
        my $minYC = $self->yValueToCoord($minY + $minBaseY);

        my $err;

        # my $err = $self->{_image}->Draw(
          # primitive => 'line',
          # points => join(',',$minYXC,$minYC,$minYXC,$self->height()-1),
          # stroke => sprintf('rgba(%s)',join(',',@$color,.25)),
        # );

        # die $err if $err;

        my $minText = sprintf('Min: %.02f', $minY) ."\n".
          OP::Utility::date($minYX) ."\n".
          OP::Utility::time($minYX);

        $err = $self->{_image}->Annotate(
          font => $self->font,
          pointsize => 11,
          x => $minYXC,
          y => $minYC,
          fill => sprintf('rgba(%s)',join(',',@$color,1)),
          text => $minText,
          align => "Center",
        );

        die $err if $err;

        my $maxYXC = $self->xValueToCoord($maxYX);
        my $maxYC = $self->yValueToCoord($maxY + $maxBaseY);

        # $err = $self->{_image}->Draw(
          # primitive => 'line',
          # points => join(',',$maxYXC,$maxYC,$maxYXC,$self->height()-1),
          # stroke => sprintf('rgba(%s)',join(',',@$color,.25)),
        # );

        # die $err if $err;

        my $maxText = sprintf('Max: %.02f', $maxY) ."\n".
          OP::Utility::date($maxYX) ."\n".
          OP::Utility::time($maxYX);

        $err = $self->{_image}->Annotate(
          font => $self->font,
          pointsize => 11,
          x => $maxYXC,
          y => $maxYC,
          fill => sprintf('rgba(%s)',join(',',@$color,1)),
          text => $maxText,
          align => "Center",
        );

        die $err if $err;
      } );

    } );

    #
    # ALWAYS FULLY UNLOAD STACKS with shift() or pop(), or suffer
    # the bloaty consequences.
    #
    while ( @{ $lineStack } ) { &{ $lineStack->shift() } }
    while ( @{ $shapeStack } ) { &{ $shapeStack->shift() } }

    my $prevXC = 0;

    $xTicks->keys()->sort(sub{ shift() <=> shift() })->each( sub {
      my $x = shift;

      if ( $prevXC + 72 > $x ) { return(); }

      $prevXC = $x;

      my $err = $self->{_image}->Draw(
        primitive => 'line',
        points => join(',',$x,0,$x,$self->height()-1),
        stroke => sprintf('rgba(%s)',$self->gridColor()->join(',')),
      );

      die $err if $err;

      if (
        ( $x == $xTicks->keys()->min() ) 
          || ( $x == $xTicks->keys()->max() )
      ) {
        return();
      }

      $err = $self->{_image}->Annotate(
        font => $self->font,
        pointsize => 9,
        x => $x + 3,
        y => 10,
        fill => sprintf('rgba(%s)',$self->unitColor()->join(',')),
        text => OP::Utility::date($xTicks->{$x}) ."\n".
          OP::Utility::time($xTicks->{$x}),
        align => "Center",
        # rotate => 90,
      );

      die $err if $err;
    } );

    while ( @{ $labelStack } ) { &{ $labelStack->shift() } }

    my @blobs = $self->{_image}->ImageToBlob();

    return $blobs[0];
  },
};
__END__
=pod

=head1 NAME

OP::SeriesChart - Experimental image-based series visualizer

=head1 SYNOPSIS

  #
  # Load Series data:
  #
  my $log = OP::Log->load($logName);

  my $series = $log->series($start, $end);

  # ... set series opts (consolidation, interpolation, etc)

  my $chart = OP::SeriesChart->new;

  $chart->setStacked(true|false);

  # ... set chart opts (dimensions, limits, etc)

  $chart->addSeries( $series );

  #
  # Render chart to a PNG image:
  #
  open(OOT, ">", "oot.png");

  print OOT $chart->render();

  close(OOT);


=head1 SEE ALSO

You might want to take a look at L<Chart::Clicker>, which is more
mature than this class but has a very similar interface. SeriesChart
will probably go away at some point, replaced with some guidance
as to how to use Series objects with Chart::Clicker.

This file is part of L<OP>.

=cut
