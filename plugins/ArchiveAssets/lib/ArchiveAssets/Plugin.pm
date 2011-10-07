package ArchiveAssets::Plugin;

use strict;
use warnings;
use MT::Template::Context;

sub _cb_cms_pre_save_asset {
    my ($cb, $app, $obj, $original) = @_;
    return 1
      unless (($obj->column_values->{class} || '') eq 'archive');
    my $tracking = $app->param('tracking') || 2;
    $obj->meta('tracking', $tracking);
}

sub _cb_param_asset_options {
    my ( $cb, $app, $param, $tmpl ) = @_;
    return unless (($param->{url} || '') =~ /zip|lzh|gz|rar$/);
    my $plugin = MT->component("ArchiveAssets");
    my $host = $tmpl->getElementById('tags')
      or return;
    my $add  = $tmpl->createElement(
        'app:setting', 
        {
            id => 'tracking',
            label => $plugin->translate('Tracking this File'),
            label_class => "no-header"
        }
    );
    my $label = $plugin->translate('Tracking this File');
    my $html  = '<input type="checkbox" name="tracking" id="tracking" value="1" />&nbsp;<label for="tracking">' . $label . '</label>';
    $add->innerHTML($html);
    $tmpl->insertBefore($add, $host);
}

sub _cb_param_edit_asset {
    my ( $cb, $app, $param, $tmpl ) = @_;
    return unless (($param->{asset_type} || '') eq 'archive');
    my $plugin = MT->component("ArchiveAssets");
    my $asset = $param->{asset};
    my $tracking = $asset->meta('tracking', @_);
    my $checked = '';
    if ($tracking->{tracking} eq 1) {
        $checked = ' checked="checked"';
    }
    my $host = $tmpl->getElementById('tags');
    my $add  = $tmpl->createElement(
        'app:setting', 
        {
            id => 'tracking',
            label => $plugin->translate('Tracking this File'),
            label_class => "no-header"
        }
    );
    my $label = $plugin->translate('Tracking this File');
    my $html  = '<input type="checkbox" name="tracking" id="tracking" value="1"' . $checked . ' />&nbsp;<label for="tracking">' . $label . '</label>';
    $add->innerHTML($html);
    $tmpl->insertBefore($add, $host);
}

sub _cb_param_asset_insert {
    my ($cb, $app, $param, $tmpl) = @_;
    my $asset = $tmpl->context->stash('asset')
      or return;
    return if ($asset->class ne 'archive');
}

sub extract_asset {
    my ($app) = @_;
    my $blog = $app->blog
      or return;
    if (! $blog ) {
        return MT->translate( 'Invalid request.' );
    }
    $app->validate_magic()
      or return MT->translate( 'Permission denied.' );
    my $user = $app->user;
    if (! is_user_can( $blog, $user, 'upload' ) ) {
        return MT->translate( 'Permission denied.' );
    }
    my @ids = $app->param('id');
    my $site_path = $blog->site_path;
    require MT::Asset;
    require File::Basename;
    foreach my $id (@ids) {
        my $asset = MT::Asset->load($id);
        next if ($asset->class ne 'archive');
        (my $directory = File::Basename::dirname( $asset->file_path ))
          =~ s!$site_path!%r!;
        my $extracted = extract(
          $asset->file_name,
          File::Basename::dirname( $asset->file_path ),
          &allowed_filename_func($app)
        );
        foreach my $file (@$extracted) {
            if (! Encode::is_utf8($file)) {
                $file = Encode::decode('utf8', $file);
            }
            $file =~ s/^\/*//;
            my $basename = File::Basename::basename($file);
            my $asset_pkg = MT::Asset->handler_for_file($basename);
            my $ext = ( File::Basename::fileparse( $file, qr/[A-Za-z0-9]+$/ ) )[2];
            my $filepath = File::Spec->catfile($directory , $file);
            my $obj = $asset_pkg->load({
                'file_path' => $filepath,
                'blog_id' => $blog->id,
            }) || $asset_pkg->new;
            my $is_new = not $obj->id;
            $obj->file_path($filepath);
            $obj->url("%r/$file");
            $obj->blog_id($blog->id);
            $obj->file_name($basename);
            $obj->file_ext($ext);
            $obj->created_by( $app->user->id );
            $obj->save();
        }
    }
    $app->call_return( extracted => 1 );
}


sub extract {
    my ($filename, $dist, $allowed_filename) = @_;

    my @files = ();
    my $err = '';
    use POSIX;
    my $cwd = getcwd();
    chdir($dist);
    if ($filename =~ m/\.tar\.gz$|\.tgz$|\.tar$/i) {
        my $compressed = $& ne '.tar';
        require Archive::Tar;
        $@ = undef;
        if ($compressed) {
            eval { require IO::Zlib; };
            $err = $@;
        }
        if (! $@) {
            my $tar = Archive::Tar->new;
            $tar->read($filename, $compressed);
            @files = $tar->list_files([ 'name', 'mtime' ]);
            require Encode::Guess;
            my $encode = sub {
                my $guess = Encode::Guess::guess_encoding(
                    join('', map($_->{'name'}, @files)),
                    qw/cp932 euc-jp iso-2022-jp/
                );
                ref $guess ? $guess->name : 'utf8';
            }->();
            @files = grep($_, map({
                my $name = $_->{'name'};
                if (! $allowed_filename->($name)) {
                    undef;
                }
                else {
                    my $new_name = Encode::encode('utf8', Encode::decode(
                        $encode, $name
                    ));
                    $tar->extract_file($name, $new_name);
                    utime($_->{'mtime'}, $_->{'mtime'}, $new_name);
                    $new_name;
                }
            } @files));
        }
    }
    elsif ($filename =~ m/\.zip$/i) {
        eval { require Archive::Zip; };
        $err = $@;
        if (! $@) {
            my $zip = Archive::Zip->new();
            $zip->read($filename);
            @files = $zip->memberNames();
            require Encode::Guess;
            my $encode = sub {
                my $guess = Encode::Guess::guess_encoding(
                    join('', @files),
                    qw/cp932 euc-jp iso-2022-jp/
                );
                ref $guess ? $guess->name : 'utf8';
            }->();
            @files = grep($_, map({
                my $m = $zip->memberNamed($_);
                if (! $allowed_filename->($_)) {
                    undef;
                }
                else {
                    my $new_name = Encode::encode('utf8', Encode::decode(
                        $encode, $_
                    ));
                    $m->extractToFileNamed($new_name);
                    $new_name;
                }
            } @files));
        }
    }
    elsif ($filename =~ m/\.rar$/i) {
        eval { require Archive::Rar; };
        $err = $@;
        if (! $@) {
            my $rar = Archive::Rar->new( -archive => $filename );
            #$rar->List( );
            my $res = $rar->Extract( );
        }
    }
    chdir($cwd);
    $err ? $err : \@files;
}

sub allowed_filename_func {
    my $app = shift;
    my (@deny_exts, @allow_exts);
    if ( my $deny_exts = $app->config->DeniedAssetFileExtensions ) {
        @deny_exts = map {
            if   ( $_ =~ m/^\./ ) { qr/$_/i }
            else                  { qr/\.$_/i }
        } split '\s?,\s?', $deny_exts;
    }
    if ( my $allow_exts = $app->config->AssetFileExtensions ) {
        @allow_exts = map {
            if   ( $_ =~ m/^\./ ) { qr/$_/i }
            else                  { qr/\.$_/i }
        } split '\s?,\s?', $allow_exts;
    }
    sub {
        my ($name) = @_;
        return undef if $name =~ /Thumbs\.db/;
        return undef if $name =~ /__MACOSX/o;
        return undef if $name =~ /\/$/;
        if (@deny_exts) {
            my @ret = File::Basename::fileparse( $name, @deny_exts );
            if ( $ret[2] ) {
                return undef;
            }
        }
        if (@allow_exts) {
            my @ret = File::Basename::fileparse( $name, @allow_exts );
            unless ( $ret[2] ) {
                return undef;
            }
        }
        return 1;
    };
}

sub is_user_can {
    my ( $blog, $user, $permission ) = @_;
    $permission = 'can_' . $permission;
    my $perm = $user->is_superuser;
    unless ( $perm ) {
        if ( $blog ) {
            my $admin = 'can_administer_blog';
            $perm = $user->permissions( $blog->id )->$admin;
            $perm = $user->permissions( $blog->id )->$permission unless $perm;
        } else {
            $perm = $user->permissions()->$permission;
        }
    }
    return $perm;
}

sub doLog {
    my ($msg) = @_; 
    return unless defined($msg);
    use MT::Log;
    use Data::Dumper;
    my $log = MT::Log->new;
    $log->message(Dumper($msg));
    $log->save or die $log->errstr;
}

1;
