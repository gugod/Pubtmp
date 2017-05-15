package Pubtmp;
use autodie;

use Dancer2;
use Digest;
use Digest::Whirlpool;
use Digest::SHA qw(sha512_base64);
use Data::UUID;
use List::Util qw(sum);
use Time::Moment;
use File::Next;
use URI::Escape qw(uri_escape uri_escape_utf8);

our $VERSION = '0.1';

use constant PUBTMP_QUOTA => "2147483648"; # 2GB
use constant PUBTMP_ROOT => "/tmp/pubtmp";

sub whirlpool_base64 {
    my ($data) = @_;
    my $d = Digest->new('Whirlpool');
    $d->add($data);
    return $d->base64digest;
}

sub generate_uuid {
    my $u = Data::UUID->new;
    my $uuid = $u->create;
    return $u->to_hexstring($uuid);
}

sub load_file_json {
    my ($filename) = @_;

    open(my $fh, "<", $filename);
    my $content = do { local $/; <$fh> };
    close($fh);

    my $data = decode_json($content);
    return $data;
}

sub write_file_json {
    my ($filename, $data) = @_;
    open(my $fh, ">", $filename) or die $!;
    print $fh encode_json($data);
    close($fh);
}

sub humanized_file_size {
    my ($n) = @_;
    return 1+int($n/1024) .    "KB" if ($n < 1048576);
    return 1+int($n/1048576) . "MB" if ($n < 1073741824);
    return sprintf("%.1fGB", $n/1073741824);
}

sub humanize_file {
    my ($file_meta_data) = @_;

    return +{
        uuid        => $file_meta_data->{uuid},
        basename    => $file_meta_data->{upload}{basename} // "unnamed",
        uploaded_at => $file_meta_data->{uploaded_at},

        size       => $file_meta_data->{upload}{size},
        size_human => humanized_file_size($file_meta_data->{upload}{size}),

        ($file_meta_data->{upload}{type} =~ /\Aimage/) ? (
            is_previewable_as_image => 1,
            url_for_previewable_image => uri_for("/file/" . uri_escape_utf8($file_meta_data->{upload}{basename}), { n => $file_meta_data->{uuid} })
        ):(),

        url_for_preview  => uri_for("/preview/" . uri_escape_utf8($file_meta_data->{upload}{basename}), { n => $file_meta_data->{uuid} }),
        url_for_download  => uri_for("/file/" . uri_escape_utf8($file_meta_data->{upload}{basename}), { n => $file_meta_data->{uuid}, dl => 1 }),
    };
}

sub gather_files_in_pubtmp {
    my @files;
    my $meta_files = File::Next::files(PUBTMP_ROOT . "/meta");
    while ( defined( my $file = $meta_files->() ) ) {
        next unless $file =~ /\.json\z/;
        my $file_meta_data = load_file_json($file);

        if (-f $file_meta_data->{storage}{path}) {
            push @files, humanize_file($file_meta_data);
        } else {
            debug "Missing in storage: $file";
        }
    }

    @files = sort { $b->{uploaded_at} cmp $a->{uploaded_at} } @files;

    return \@files;
}

sub file_lookup_by_uuid {
    my ($uuid) = @_;

    my $found;
    my $meta_files = File::Next::files(PUBTMP_ROOT . "/meta");
    while ( !$found && defined( my $file = $meta_files->() ) ) {
        next unless $file =~ /\.json\z/;
        my $file_meta_data = load_file_json($file);

        next unless $file_meta_data->{uuid} eq $uuid && -f $file_meta_data->{storage}{path};
        $found = $file_meta_data;
    }
    return $found;
}

sub unlink_by_uuid_if_exists {
    my ($uuid) = @_;
    my $fmd = file_lookup_by_uuid($uuid) or return;

    unlink($fmd->{storage}{path});
    unlink($fmd->{meta}{path});

    return 1;
}

get '/' => sub {
    my $files = gather_files_in_pubtmp();

    my $folder_size_used = sum(map{ $_->{size} }@$files) // 0;
    my $folder_size_free = PUBTMP_QUOTA - $folder_size_used;
    template 'index' => {
        'title' => '/pub/tmp/',
        pubtmp_folder_size_free_human => humanized_file_size($folder_size_free),
        pubtmp_folder_size_used_human => humanized_file_size($folder_size_used),
        pubtmp_folder_quota_human     => humanized_file_size(PUBTMP_QUOTA),
        pubtmp_file_list => $files,
    };
};

get '/preview/:basename' => sub {
    my $file_meta_data = file_lookup_by_uuid( param("n") ) or do {
        redirect "/";
        return;
    };

    template 'preview' => {
        'title' => '/pub/tmp/ ' . param("basename"),
        file => humanize_file( $file_meta_data )
    };
};

get '/file/:basename' => sub {
    my $file_meta_data = file_lookup_by_uuid( param("n") ) or do {
        redirect "/";
        return;
    };

    send_file($file_meta_data->{storage}{path}, system_path => 1);
};

del '/file/:uuid' => sub {
    unlink_by_uuid_if_exists( param("uuid") );
    redirect "/";
};

post '/file/:uuid' => sub {
    if (param("_method") eq "delete") {
        unlink_by_uuid_if_exists( param("uuid") );
    }
    redirect "/";
};

post '/' => sub {
    my $upload = upload("f");
    unless ($upload) {
        redirect "/";
        return;
    }

    my $uuid = generate_uuid();
    my $path = PUBTMP_ROOT . "/store/$uuid";

    my $basename = $upload->basename;
    $basename =~ s/\p{Noncharacter_Code_Point}//g;

    my $upload_content = $upload->content;
    my $file_meta_data = {
        uuid => $uuid,
        digest => {
            sha512_base64 => sha512_base64( $upload_content ),
            whirlpool_base64 => whirlpool_base64( $upload_content ),
        },
        basename_ext => ((lc($basename) =~ m{\.([^\.]+)\z})[0] // ""),
        upload => {
            type     => $upload->type,
            basename => $basename,
            headers  => $upload->headers,
            size     => (stat($upload->file_handle))[7],
        },
        storage => {
            type => "filesystem",
            path => $path,
        },
        meta => {
            path => PUBTMP_ROOT . "/meta/$uuid.json",
        },
        uploaded_at => Time::Moment->now->strftime("%Y-%m-%dT%H:%M:%S%f%Z"),
    };

    debug "The filename is $path";

    write_file_json($file_meta_data->{meta}{path} , $file_meta_data);

    $upload->copy_to($path);

    redirect "/";
};

for(PUBTMP_ROOT, PUBTMP_ROOT."/meta", PUBTMP_ROOT."/store") {
    mkdir($_) unless -d $_;
}

true;
