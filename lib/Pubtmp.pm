package Pubtmp;
use autodie;

use Dancer2;
use Digest;
use Time::Moment;
use File::Next;

our $VERSION = '0.1';

use constant PUBTMP_ROOT => "/tmp/pubtmp";

sub generate_random_name {
    my ($upload) = @_;
    my ($ext) = lc($upload->basename) =~ m{\.([^\.]+)\z};
    my $d = Digest->new("SHA-512");
    $d->add( $upload->content );
    return $d->hexdigest . '-' . time() . '.' . $ext;
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

                link_to_download => "/dl/" . $meta_data->{name},
            };
        } else {
            debug "Missing in storage: $file";
        }
    }

    return \@files;
}

sub file_lookup_by_name {
    my ($name) = @_;
    my $found;
    my $meta_files = File::Next::files(PUBTMP_ROOT . "/meta");
    while ( !$found && defined( my $file = $meta_files->() ) ) {
        next unless $file =~ /\.json\z/;
        my $meta_data = load_file_json($file);

        next unless $meta_data->{name} eq $name && -f $meta_data->{storage}{path};
        $found = $meta_data->{storage}{path};
    }
    return $found;
}

get '/' => sub {
    my $files = gather_files_in_pubtmp();
    template 'index' => { 'title' => 'Pubtmp', pubtmp_file_list => $files };
};

get '/dl/:name' => sub {
    debug "Download: " . param("name");
    my $path = file_lookup_by_name( param("name") );

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
        my $name = generate_random_name( $upload );
        debug "The filename is $name";

        my $path = PUBTMP_ROOT . "/stash/$name";
        write_file_json( PUBTMP_ROOT . "/meta/$name.json", {
            name => $name,
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
        });

        $upload->link_to($path);
    }

    redirect "/";
};

true;
