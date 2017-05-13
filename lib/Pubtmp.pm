package Pubtmp;
use autodie;

use Dancer2;
use Digest;
use Digest::Whirlpool;
use Digest::SHA qw(sha512_base64);
use Data::UUID;
use Time::Moment;
use File::Next;

our $VERSION = '0.1';

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

sub gather_files_in_pubtmp {
    my @files;
    my $meta_files = File::Next::files(PUBTMP_ROOT . "/meta");
    while ( defined( my $file = $meta_files->() ) ) {
        next unless $file =~ /\.json\z/;
        my $meta_data = load_file_json($file);

        if (-f $meta_data->{storage}{path}) {
            push @files, {
                basename => $meta_data->{upload}{basename},
                uploaded_at => $meta_data->{uploaded_at},

                size       => $meta_data->{upload}{size},
                size_human => humanized_file_size($meta_data->{upload}{size}),

                link_to_download => "/file/" . $meta_data->{upload}{basename} . "?n=" . $meta_data->{uuid},
                link_to_delete   => "/file/" . $meta_data->{upload}{basename} . "?n=" . $meta_data->{uuid} . "&_method=delete",
            };
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
        my $meta_data = load_file_json($file);

        next unless $meta_data->{uuid} eq $uuid && -f $meta_data->{storage}{path};
        $found = $meta_data->{storage}{path};
    }
    return $found;
}

get '/' => sub {
    my $files = gather_files_in_pubtmp();
    template 'index' => { 'title' => 'Pubtmp', pubtmp_file_list => $files };
};

get '/file/:basename' => sub {
    my $path = file_lookup_by_uuid( param("n") );
    if ($path) {
        debug "The file: $path";
        send_file($path, system_path => 1);
    } else {
        redirect "/";
    }
};

post '/' => sub {
    my $upload = upload("f");
    debug "The upload is $upload";
    if ($upload) {
        my $uuid = generate_uuid();
        my $path = PUBTMP_ROOT . "/store/$uuid";

        my $upload_content = $upload->content;
        my $meta_data = {
            uuid => $uuid,
            digest => {
                sha512_base64 => sha512_base64( $upload_content ),
                whirlpool_base64 => whirlpool_base64( $upload_content ),
            },
            basename_ext => ((lc($upload->basename) =~ m{\.([^\.]+)\z})[0] // ""),
            upload => {
                type     => $upload->type,
                basename => $upload->basename,
                headers  => $upload->headers,
                size     => (stat($upload->file_handle))[7],
            },
            storage => {
                type => "filesystem",
                path => $path,
            },
            uploaded_at => Time::Moment->now->strftime("%Y-%m-%dT%H:%M:%S%f%Z"),
        };

        debug "The filename is $path";

        write_file_json( PUBTMP_ROOT . "/meta/$uuid.json", $meta_data);

        $upload->copy_to($path);
    }

    redirect "/";
};

for(PUBTMP_ROOT, PUBTMP_ROOT."/meta", PUBTMP_ROOT."/store") {
    mkdir($_) unless -d $_;
}

true;
