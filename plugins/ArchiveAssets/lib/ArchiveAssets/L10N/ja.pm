package ArchiveAssets::L10N::ja;

use strict;
use base 'ArchiveAssets::L10N::en_us';
use vars qw( %Lexicon );

## The following is the translation table.

%Lexicon = (
	'Allowing users to upload Archives into their Movable Type.' => '圧縮ファイルをアイテムとして扱う機能をMovable Typeに追加します。',
	'Insert GoogleAnalytics PageTracker code:' => 'GoogleAnalytics PageTrackerコードを挿入する:',
	'Extract and Delete Archives:' => '解凍後にアーカイブを削除する:',
	'Overwrite Extracted Files(If Exist Same File(s)).:' => '同名のファイルは、解凍されたファイルで上書きする:',
	'Extract' => 'アーカイブを解凍する',
	'Archive' => '圧縮ファイル',
	'Archives' => '圧縮ファイル',
	'Tracking this File' => 'このファイルをTrackingする',
	'Extract Archive' => '圧縮ファイルを解凍する',
	'Delete Archive at Extracted.' => '解凍後に圧縮ファイルを削除する',
	'Make Index Templates(for Text Asset).:' => 'テキストのアイテムをインデックステンプレートとして作成する:',
	'Overwrite Templates(If Same outfile).:' => '出力ファイルが同じテンプレートを上書きする:',
	'Replace tabs to spaces(in Templates):' => 'テンプレートのタブをスペースに置き換える:',
	'Cleanup Templates:' => 'テンプレートを整形する:',
	'Make Text files as Index Templates.' => 'テキストファイルをインデックステムプレートに登録する',
	'such as css,js or html.' => 'css、jsやhtmlなど.',
	'Overwrite Index Templates of same Outfile.' => '出力ファイル名が同じテンプレートを上書きする',
	'turn off this. always create new index template.' => 'オフにした場合、常に新規テンプレートが作成されます',
	'Make Entries with Asset.' => 'アイテムからブログ記事を作成する',
	'Category Label:' => 'カテゴリー名:',
	'Category Basename:' => 'カテゴリーベースネーム:',
	'Use ExifDate for extracted Asset created on:' => 'Exif情報の作成日をアイテム作成日として使用する',
);

1;

