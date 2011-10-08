package MT::Asset::Archive;

use strict;
use base qw(MT::Asset);

__PACKAGE__->install_properties({
    class_type => 'archive',
    column_defs => {
        'tracking' => 'integer meta',
    },
});

sub extensions {
    my $pkg = shift;
    return $pkg->SUPER::extensions([
        qr/zip/i,
        qr/gz/i,
        qr/lzh/i,
        qr/rar/i,
    ]);
}


sub class_label {
    MT->translate('Archive');
}

sub class_label_plural {
    MT->translate('Archives');
}

sub has_thumbnail { 0; }

sub as_html {
    my $asset = shift;
    my ($param) = @_;

    my $url      = $asset->url;
    my $label    = $asset->label;
    my $fname    = $asset->file_name;
    my $tracking;

    if ($param->{tracking}) {
        $tracking = $param->{tracking};
        $asset->meta('tracking', $tracking);
        if ($asset->id) {
            $asset->save;
        }
    } elsif ($asset->tracking) {
        $tracking = $asset->tracking;
    }
    my $html = sprintf '<a href="%s">%s</a>',
        MT::Util::encode_html($asset->url),
        MT::Util::encode_html($fname);
    if ($tracking eq 1) {
        my $track_code = 'onclick="javascript:_gaq.push([\'_trackPageview\', this.pathname]);" ';
        $html =~ s/<a /<a $track_code/i;
    }
    return $param->{enclose} ? $asset->enclose($html) : $html;
}

sub metadata {
    my $obj  = shift;
    my $meta = $obj->SUPER::metadata(@_);
    my $tracking = $obj->tracking;
    $meta;
}

sub tracking {
    my $asset = shift;
    my $tracking = $asset->meta('tracking', @_);
    return $tracking;
}

1;