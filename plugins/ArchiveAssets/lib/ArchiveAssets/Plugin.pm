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

sub _cb_cms_upload_archive {
    my ( $eh, %args ) = @_;
    my $app = MT->instance();
    return unless ( $app->param( 'extract_zip' ) );
    return if ( $app->param( 'dialog' ) );
    my $blog = $app->blog
      or return;
    if (! $blog ) {
        return MT->translate( 'Invalid request.' );
    }
    $app->validate_magic()
      or return MT->translate( 'Permission denied.' );
    my $user = $app->user
      or return;
    if (! is_user_can( $blog, $user, 'upload' ) ) {
        return MT->translate( 'Permission denied.' );
    }
    my $plugin = MT->component( 'ArchiveAssets' );
    (my $filename = $args{ file }) =~ s!\\!/!g;;
    require File::Basename;
    (my $site_path = $blog->site_path) =~ s!\\!/!g;
    (my $directory = File::Basename::dirname( $filename ))  =~ s!\\!/!g;
    my $extracted = extract(
      File::Basename::basename( $filename ),
      $directory,
      &allowed_filename_func($app)
    );
    $directory  =~ s!$site_path!%r!;
    require MT::Asset;
    foreach my $file (@$extracted) {
        if (! Encode::is_utf8($file)) {
            $file = Encode::decode('utf8', $file);
        }
        $file =~ s/^\/*//;
        my $basename = File::Basename::basename($file);
        my $asset_pkg = MT::Asset->handler_for_file($basename);
        my $ext = ( File::Basename::fileparse( $file, qr/[A-Za-z0-9]+$/ ) )[2];
        (my $filepath = File::Spec->catfile($directory , $file)) =~ s!\\!/!g;
        require LWP::MediaTypes;
        my $mimetype = LWP::MediaTypes::guess_media_type($filepath);
        my $obj = $asset_pkg->load({
            'file_path' => $filepath,
            'blog_id' => $blog->id,
        }) || $asset_pkg->new;
        my $is_new = not $obj->id;
        $filepath =~ s!$site_path!%r!;
        $obj->label($basename) if $is_new;
        $obj->file_path($filepath);
        $obj->url($filepath);
        $obj->blog_id($blog->id);
        $obj->file_name($basename);
        $obj->file_ext($ext);
        $is_new ? $obj->created_by( $app->user->id ) : $obj->modified_by( $app->user->id );
        $obj->mime_type($mimetype) if $mimetype;
        $obj->save();
    }
    my $asset = $args{ asset };
    $asset->remove or die $asset->errstr
      if $app->param( 'delete_asset' );
}

sub _cb_param_asset_upload {
    my ( $cb, $app, $param, $tmpl ) = @_;
    return unless ( $tmpl->name eq 'include/asset_upload.tmpl' );
    return if $app->param( 'dialog_view' );
    eval { require Archive::Zip };
    return if $@;
    my $blog = $app->blog
      or return;
    if (! $blog ) {
        return MT->translate( 'Invalid request.' );
    }
    my $user = $app->user;
    if (! is_user_can( $blog, $user, 'upload' ) ) {
        return MT->translate( 'Permission denied.' );
    }
    my $plugin = MT->component( 'ArchiveAssets' );
    my $pointer_field = $tmpl->getElementById( 'file' );
    my $nodeset = $tmpl->createElement( 'app:setting', {
        id => 'extract_zip',
        label => $plugin->translate( 'Archive' ),
        label_class => 'no-header',
        required => 0,
    } );
    my $innerHTML = <<MTML;
        <label><input type="checkbox" name="extract_zip" id="extract_zip" value="1" />
        <__trans_section component="ArchiveAssets"><__trans phrase="Extract Archive"></__trans_section>
        </label>
        <script type="text/javascript">
        jQuery(function() {
            var setting = jQuery("#extract_zip-field").hide();
            jQuery("#file").change(function() {
                if (/\\.zip\$/.test(jQuery(this).val().toLowerCase())) {
                    setting.show();
                } else if (/\\.tz\$/.test(jQuery(this).val().toLowerCase())) {
                    setting.show();
                } else {
                    setting.hide();
                }
            });
        });
        </script>
MTML
    $nodeset->innerHTML( $innerHTML );
    $tmpl->insertAfter( $nodeset, $pointer_field );

    $pointer_field = $tmpl->getElementById( 'extract_zip' );
    $nodeset = $tmpl->createElement( 'app:setting', {
        id => 'delete_asset',
        label => $plugin->translate( 'Delete Archive at Extracted.' ),
        label_class => 'no-header',
        required => 0,
    } );
    $innerHTML = <<'MTML';
        <label><input type="checkbox" name="delete_asset" id="delete_asset" value="1" />
        <__trans_section component="ArchiveAssets"><__trans phrase="Delete Archive at Extracted."></__trans_section>
        </label>
        <script type="text/javascript">
        jQuery(function() {
            var delete_archive = jQuery("#delete_asset-field").hide();
            jQuery("#extract_zip").click(function() {
                delete_archive[jQuery(this).attr("checked") ? "show" : "hide"]();
            });
        });
        </script>
MTML
    if ( $plugin->get_config_value('delete_extracted', 'blog:'.$blog->id) || 0 ) {
        $innerHTML .= <<'MTML';
        <script type="text/javascript">
        jQuery(function() {
            jQuery("#delete_asset").attr('checked', true);
        });
        </script>
MTML
    }
    $nodeset->innerHTML( $innerHTML );
    $tmpl->insertAfter( $nodeset, $pointer_field );
}

sub _cb_source_asset_replace {
    my ($cb, $app, $tmpl) = @_;
    return unless ( $app->param( 'extract_zip' ) );
    return if ( $app->param( 'dialog_view' ) );
    my $blog = $app->blog
      or return;
    if (! $blog ) {
        return MT->translate( 'Invalid request.' );
    }
    $app->validate_magic()
      or return MT->translate( 'Permission denied.' );
    my $delete_extracted = $app->param( 'delete_asset' ) || 0;
    my $field = qq{
    <input type="hidden" name="extract_zip" id="extract_zip" value="1" />
    <input type="hidden" name="delete_asset" id="delete_asset" value="$delete_extracted" />
    };
    my $old = qq{<div class="error-message">};
    $$tmpl =~ s!$old!$field$old!;
}

sub _cb_cms_filtered_list_param_asset {
    my $cb = shift;
    my ( $app, $res, $objs ) = @_;
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
    my $plugin = MT->component("ArchiveAssets");
    my $delete_extracted = $plugin->get_config_value('delete_extracted', 'blog:'.$blog->id) || 0;
    my @ids = $app->param('id');
    require MT::Asset;
    require File::Basename;
    (my $site_path = $blog->site_path) =~ s!\\!/!g;
    foreach my $id (@ids) {
        my $asset = MT::Asset->load($id);
        next if ($asset->class ne 'archive');
        (my $directory = File::Basename::dirname( $asset->file_path ))  =~ s!\\!/!g;
        $directory  =~ s!$site_path!%r!;
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
            (my $filepath = File::Spec->catfile($directory , $file)) =~ s!\\!/!g;
            require LWP::MediaTypes;
            my $mimetype = LWP::MediaTypes::guess_media_type($filepath);
            my $obj = $asset_pkg->load({
                'file_path' => $filepath,
                'blog_id' => $blog->id,
            }) || $asset_pkg->new;
            my $is_new = not $obj->id;
            $filepath =~ s!$site_path!%r!;
            $obj->label($basename) if $is_new;
            $obj->file_path($filepath);
            $obj->url($filepath);
            $obj->blog_id($blog->id);
            $obj->file_name($basename);
            $obj->file_ext($ext);
            $is_new ? $obj->created_by( $app->user->id ) : $obj->modified_by( $app->user->id );
            $obj->mime_type($mimetype) if $mimetype;
            $obj->save();
        }
        $asset->remove or die $asset->errstr
          if $delete_extracted;
    }
    $app->call_return( extracted => 1 );
}

sub extract_current {
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
    require MT::Asset;
    require File::Basename;
    (my $site_path = $blog->site_path) =~ s!\\!/!g;
    my $asset = MT::Asset->load($app->param('id'))
      or return;
    next if ($asset->class ne 'archive');
    (my $directory = File::Basename::dirname( $asset->file_path ))  =~ s!\\!/!g;
    $directory  =~ s!$site_path!%r!;
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
        (my $filepath = File::Spec->catfile($directory , $file)) =~ s!\\!/!g;
        require LWP::MediaTypes;
        my $mimetype = LWP::MediaTypes::guess_media_type($filepath);
        my $obj = $asset_pkg->load({
            'file_path' => $filepath,
            'blog_id' => $blog->id,
        }) || $asset_pkg->new;
        my $is_new = not $obj->id;
        $filepath =~ s!$site_path!%r!;
        $obj->label($basename) if $is_new;
        $obj->file_path($filepath);
        $obj->url($filepath);
        $obj->blog_id($blog->id);
        $obj->file_name($basename);
        $obj->file_ext($ext);
        $is_new ? $obj->created_by( $app->user->id ) : $obj->modified_by( $app->user->id );
        $obj->mime_type($mimetype) if $mimetype;
        $obj->save();
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

sub _is_archive {
    my $asset = shift;
    (($asset->class || '') eq 'archive') ? return 1 : return 0;
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
