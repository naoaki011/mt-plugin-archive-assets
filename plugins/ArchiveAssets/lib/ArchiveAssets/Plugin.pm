package ArchiveAssets::Plugin;

use strict;
use warnings;
use MT::Template::Context;
use MT::Util qw( offset_time_list dirify );

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
    my $upload_html = $param->{ upload_html };

    $param->{ upload_html } = $upload_html;
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
    (my $current = File::Basename::dirname( $filename ))  =~ s!\\!/!g;
    my $extracted = extract(
      File::Basename::basename( $filename ),
      $current,
      &allowed_filename_func($app)
    );
    my $upload_mode = (~ oct($app->config('UploadUmask'))) & oct('777');
    my $dir_mode = (~ oct($app->config('DirUmask'))) & oct('777');
    my @files = grep({ $_ } map({
        my $path = File::Spec->catfile($current, $_);
        if (-d $path) {
            chmod($dir_mode, $path);
            '';
        }
        else {
            chmod($upload_mode, $path);
            [ File::Spec->catfile($current, $_), $path ];
        }
    } @$extracted));
    (my $directory = $current) =~ s!$site_path!%r!;
    my $cb = $user->text_format || $blog->convert_paras;
    $cb = '__default__' if $cb eq '1';
    require MT::Asset;
    foreach my $file (@$extracted) {
        next if ($file =~ /\/$/);
        if (! Encode::is_utf8($file)) {
            $file = Encode::decode('utf8', $file);
        }
        $file =~ s/^\/*//;
        my $basename = File::Basename::basename($file);
        my $ext = ( File::Basename::fileparse( $file, qr/[A-Za-z0-9]+$/ ) )[2];
        my $asset_pkg = MT::Asset->handler_for_file($basename);
        (my $filepath = File::Spec->catfile($directory , $file)) =~ s!\\!/!g;
        if ( ($basename =~ m/\.html?$|\.mtml$|\.tmpl$|\.php$|\.jsp$|\.asp$|\.css$|\.js$/i)
          && $app->param( 'make_index' ) ) {
            my $identifier = dirify(( File::Basename::fileparse( $file, qr/\.[A-Za-z0-9]+$/ ) )[0] . '_' . $ext);
            my $tmpl_class = MT->model('template');
            my $content = do{
                open(my $fh, '<', File::Spec->catfile($current, $file));
                local $/;
                <$fh>;
            };
            $content =~ s!\t!    !g
              if ( $plugin->get_config_value('replace_tabstop', 'blog:'.$blog->id) || 1 );
            $content =~ s!\s+\n!\n!g
              if ( $plugin->get_config_value('cleanup_templates', 'blog:'.$blog->id) || 1 );
            (my $outfile = File::Spec->catfile($current, $file)) =~ s!\\!/!g;
            $outfile =~ s!$site_path!!;
            $outfile =~ s!^/!!;
            my $obj = $tmpl_class->load({
                'outfile' => $outfile,
                'blog_id' => $blog->id,
            }) || $tmpl_class->new;
            my $is_new = not $obj->id;
            $is_new = 1 unless ($app->param('overwrite_index') || 0);
            $obj->identifier($identifier || undef) unless ($obj->identifier);
            my $template_name = $is_new ? $basename : $obj->name;
            if ($is_new) {
                $obj->id( undef );
                my $ident_obj = $tmpl_class->load({
                    'identifier' => $obj->identifier,
                    'blog_id' => $blog->id,
                });
                if ($ident_obj) {
                    $obj->identifier( undef );
                }
                my $name_obj = $tmpl_class->load({
                    'name' => $template_name,
                    'blog_id' => $blog->id,
                });
                if ($name_obj) {
                    my @tl = &offset_time_list( time, $blog );
                    my $ts = sprintf "_%04d%02d%02d%02d%02d%02d", $tl[ 5 ] + 1900, $tl[ 4 ] + 1, @tl[ 3, 2, 1, 0 ];
                    $template_name .= $ts;
                }
            }
            $obj->name($template_name);
            $obj->blog_id($blog->id);
            $obj->text($content);
            $obj->outfile($outfile);
            $obj->type('index');
            $obj->save()
              or die $obj->errstr;
        }
        else {
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
            eval { require Image::ExifTool; };
            if (!$@) {
                my $exif = new Image::ExifTool;
                if (my $exif_data = $exif->ImageInfo( $obj->file_path )) {
                    if ($plugin->get_config_value('use_exifdate', 'blog:'.$blog->id) || 0) {
                        my $date = $exif_data->{ 'DateTimeOriginal' } || '';
                        if ($date) {
                            my ($year, $mon, $day, $hour, $min, $sec)
                              = ($date =~ /(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)/);
                            my $ts = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year, $mon-1, $day, $hour, $min, $sec);
                            $obj->created_on( $ts ) if $is_new;
                           $obj->modified_on( $ts ) if $is_new;
                        }
                    }
                #    my $rotation = $exif_data->{Orientation} || '';
                #    my $gps = $exif_data->{GPSPosition} || '';
                #    my $gpslon = $exif_data->{GPSLongitude} || '';
                #    my $gpslat = $exif_data->{GPSLatitude} || '';
                }
            }
            $obj->save()
              or die $obj->errstr;
            if ($is_new && ($app->param('make_entry') || 0) && ( $app->config->Asset2Entry || $blog->theme_id eq 'photogallery_blog' || 0 )) {
                if (is_user_can( $blog, $user, 'create_post' )) {
                    my ($entry, $category);
                    my $asset_basename = (File::Basename::fileparse( $obj->file_name, qr/\.[A-Za-z0-9]+$/ ))[0];
                    my $entry_title = (dirify($asset_basename) || 'untitled' . $obj->id);
                    my $entry_basename = lc($entry_title);
                    require MT::Entry;
                    $entry = MT::Entry->new;
                    $entry->title($entry_title);
                    $entry->basename($entry_basename);
                    $entry->status(MT::Entry::HOLD());
                    $entry->author_id($user->id);
                    $entry->text('');
                    $entry->convert_breaks($cb);
                    $entry->blog_id($blog->id);
                    $entry->class('entry');
                    $entry->save
                      or die $entry->errstr;
                    require MT::ObjectAsset;
                    my $object = MT::ObjectAsset->new;
                    $object->blog_id($blog->id);
                    $object->asset_id($obj->id);
                    $object->object_id($entry->id);
                    $object->object_ds('entry');
                    $object->save
                      or die $object->errstr;
                    require MT::Category;
                    my $category_label = ($app->param('category_label') || '');
                    my $category_basename = ($app->param('category_basename') || lc($app->param('category_label')) || '');
                    $category = MT::Category->load({
                        'label' => $category_label,
                        'blog_id' => $blog->id,
                    });
                    if (! $category) {
                        if ( is_user_can( $blog, $user, 'edit_categories' ) ) {
                            $category = MT::Category->new;
                            $category->label($category_label);
                            $category->basename($category_basename);
                            $category->blog_id($blog->id);
                            $category->class('category');
                            $category->save
                              or die $category->errstr;
                        }
                        else {
                            doLog( 'Create Category Permission denied.' );
                        }
                    }
                    require MT::Placement;
                    my $placement = MT::Placement->new;
                    $placement->blog_id($blog->id);
                    $placement->category_id($category->id);
                    $placement->entry_id($entry->id);
                    $placement->is_primary(1);
                    $placement->save
                      or die $placement->errstr;
                }
                else {
                    doLog( 'Create Entry Permission denied.' );
                }
            }
        }
    }
    my $asset = $args{ asset };
    $asset->remove
      or die $asset->errstr
      if $app->param( 'delete_asset' );
}

sub _cb_param_asset_upload {
    my ( $cb, $app, $param, $tmpl ) = @_;
    return unless ( ($tmpl->name || '') eq 'include/asset_upload.tmpl' );
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
    if ( $plugin->get_config_value('delete_extracted', 'blog:'.$blog->id) || 1 ) {
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

    $pointer_field = $tmpl->getElementById( 'delete_asset' );
    $nodeset = $tmpl->createElement( 'app:setting', {
        id => 'make_index',
        label => $plugin->translate( 'Make Text files as Index Templates.' ),
        label_class => 'no-header',
        required => 0,
    } );
    $innerHTML = <<'MTML';
        <label><input type="checkbox" name="make_index" id="make_index" value="1" />
        <__trans_section component="ArchiveAssets"><__trans phrase="Make Text files as Index Templates."></__trans_section>
        </label>
        <script type="text/javascript">
        jQuery(function() {
            var make_index = jQuery("#make_index-field").hide();
            jQuery("#extract_zip").click(function() {
                make_index[jQuery(this).attr("checked") ? "show" : "hide"]();
            });
        });
        </script>
        <span class="hint"><__trans_section component="ArchiveAssets"><__trans phrase="such as css,js or html."></__trans_section></span>

MTML
    if ( $plugin->get_config_value('makeindex_templates', 'blog:'.$blog->id) || 1 ) {
        $innerHTML .= <<'MTML';
        <script type="text/javascript">
        jQuery(function() {
            jQuery("#make_index").attr('checked', true);
        });
        </script>
MTML
    }
    $nodeset->innerHTML( $innerHTML );
    $tmpl->insertAfter( $nodeset, $pointer_field );

    $pointer_field = $tmpl->getElementById( 'make_index' );
    $nodeset = $tmpl->createElement( 'app:setting', {
        id => 'overwrite_index',
        label => $plugin->translate( 'Overwrite Index Templates of same Outfile.' ),
        label_class => 'no-header',
        required => 0,
    } );
    $innerHTML = <<'MTML';
        <label><input type="checkbox" name="overwrite_index" id="overwrite_index" value="1" />
        <__trans_section component="ArchiveAssets"><__trans phrase="Overwrite Index Templates of same Outfile."></__trans_section>
        </label>
        <script type="text/javascript">
        jQuery(function() {
            var overwrite_index = jQuery("#overwrite_index-field").hide();
            jQuery("#extract_zip").click(function() {
                overwrite_index[jQuery(this).attr("checked") ? "show" : "hide"]();
            });
            jQuery("#make_index").click(function() {
                overwrite_index[jQuery(this).attr("checked") ? "show" : "hide"]();
            });
        });
        </script>
        <span class="hint"><__trans_section component="ArchiveAssets"><__trans phrase="turn off this. always create new index template."></__trans_section></span>
MTML
    if ( $plugin->get_config_value('overwrite_templates', 'blog:'.$blog->id) || 1 ) {
        $innerHTML .= <<'MTML';
        <script type="text/javascript">
        jQuery(function() {
            jQuery("#overwrite_index").attr('checked', true);
        });
        </script>
MTML
    }
    $nodeset->innerHTML( $innerHTML );
    $tmpl->insertAfter( $nodeset, $pointer_field );

    $pointer_field = $tmpl->getElementById( 'overwrite_index' );
    $nodeset = $tmpl->createElement( 'app:setting', {
        id => 'make_entry',
        label => $plugin->translate( 'Make Entries with Asset.' ),
        label_class => 'no-header',
        required => 0,
    } );
    $innerHTML = <<'MTML';
        <label><input type="checkbox" name="make_entry" id="make_entry" value="1" />
        <__trans_section component="ArchiveAssets"><__trans phrase="Make Entries with Asset."></__trans_section>
        </label><br />
        <__trans_section component="ArchiveAssets"><__trans phrase="Category Label:"></__trans_section>
        <input type="text" name="category_label" value="<mt:var name="category_label" escape="html">" id="category_label" class="text" style="width:20em;" />
        <__trans_section component="ArchiveAssets"><__trans phrase="Category Basename:"></__trans_section>
        <input type="text" name="category_basename" value="<mt:var name="category_basename" escape="html">" id="category_basename" class="text" style="width:20em;" />
        <script type="text/javascript">
        jQuery(function() {
            var make_entry = jQuery("#make_entry-field").hide();
            jQuery("#extract_zip").click(function() {
                make_entry[jQuery(this).attr("checked") ? "show" : "hide"]();
            });
        });
        </script>

MTML
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
    my $plugin = MT->component( 'ArchiveAssets' );
    my $delete_extracted = $app->param( 'delete_asset' ) || $plugin->get_config_value('delete_extracted', 'blog:'.$blog->id) || 1;
    my $make_index = $app->param( 'make_index' ) || $plugin->get_config_value('makeindex_templates', 'blog:'.$blog->id) || 0;
    my $overwrite_index = $app->param( 'overwrite_index' ) || $plugin->get_config_value('overwrite_templates', 'blog:'.$blog->id) || 0;
    my $make_entry = $app->param( 'make_entry' ) || $app->config->Asset2Entry || $blog->theme_id eq 'photogallery_blog' || 0;
    my $category_label = $app->param( 'category_label' ) || '';
    my $category_basename = $app->param( 'category_basename' ) || '';
    my $field = qq{
    <input type="hidden" name="extract_zip" id="extract_zip" value="1" />
    <input type="hidden" name="delete_asset" id="delete_asset" value="$delete_extracted" />
    <input type="hidden" name="make_index" id="make_index" value="$make_index" />
    <input type="hidden" name="overwrite_index" id="overwrite_index" value="$overwrite_index" />
    <input type="hidden" name="make_entry" id="make_entry" value="$make_entry" />
    <input type="hidden" name="category_label" id="category_label" value="$category_label" />
    <input type="hidden" name="category_basename" id="category_basename" value="$category_basename" />
    };
    my $old = qq{<div class="error-message">};
    $$tmpl =~ s!$old!$field$old!;
}

sub _cb_cms_filtered_list_param_asset {
    my $cb = shift;
    my ( $app, $res, $objs ) = @_;
    
    return 1;
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
    my $delete_extracted = $plugin->get_config_value('delete_extracted', 'blog:'.$blog->id) || 1;
    my @ids = $app->param('id');
    require MT::Asset;
    require File::Basename;
    my $upload_mode = (~ oct($app->config('UploadUmask'))) & oct('777');
    my $dir_mode = (~ oct($app->config('DirUmask'))) & oct('777');
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
        my @files = grep({ $_ } map({
            my $path = File::Spec->catfile($directory, $_);
            if (-d $path) {
                chmod($dir_mode, $path);
                '';
            }
            else {
                chmod($upload_mode, $path);
                [ File::Spec->catfile($directory, $_), $path ];
            }
        } @$extracted));
        foreach my $file (@$extracted) {
            next if ($file =~ /\/$/);
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
    my $upload_mode = (~ oct($app->config('UploadUmask'))) & oct('777');
    my $dir_mode = (~ oct($app->config('DirUmask'))) & oct('777');
    my @files = grep({ $_ } map({
        my $path = File::Spec->catfile($directory, $_);
        if (-d $path) {
            chmod($dir_mode, $path);
            '';
        }
        else {
            chmod($upload_mode, $path);
            [ File::Spec->catfile($directory, $_), $path ];
        }
    } @$extracted));
    foreach my $file (@$extracted) {
        next if ($file =~ /\/$/);
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
        return undef if $name =~ /\.DS_Store/;
        return undef if $name =~ /__MACOSX/o;
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
    my $app = MT->instance;
    my $blog = $app->blog;
    return 0 if (!$blog );
    (($asset->class || '') eq 'archive') ? return 1 : return 0;
}

sub _is_blog {
    my $app = MT->instance;
    my $blog = $app->blog;
    return 0 if (!$blog );
    return 1
      if ( $blog->id && $blog->parent_id );
    return 0;
}

sub _has_blog {
    my $app = MT->instance;
    my $blog = $app->blog;
    return 0 if (!$blog );
    return 1;
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

sub _cb_source_blog_config {
    my ( $cb, $app, $tmpl ) = @_;
    my $disp = 'hidden';
    eval { require Image::ExifTool; };
    if (!$@) {
        $disp = 'block';
    }
    $$tmpl =~ s/\*show_use_exifdate\*/$disp/sg;
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
