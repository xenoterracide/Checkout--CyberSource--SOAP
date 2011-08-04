package Checkout::CyberSource::SOAP;
use Moose;
BEGIN {
    our $VERSION = '0.08'; # VERSION
}
use SOAP::Lite;
use Time::HiRes qw/gettimeofday/;
use namespace::autoclean;

use Checkout::CyberSource::SOAP::Response;

use 5.008_001;

has 'id' => (
    is  => 'ro',
    isa => 'Str',
);

has 'key' => (
    is  => 'ro',
    isa => 'Str',
);

has 'production' => (
    is  => 'ro',
    isa => 'Bool',
);

has 'column_map' => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
);

has 'response' => (
    is      => 'rw',
    isa     => 'Checkout::CyberSource::SOAP::Response',
    lazy    => 1,
    builder => '_get_response',
);

has 'test_server' => (
    is      => 'ro',
    isa     => 'Str',
    default => 'ics2wstest.ic3.com',
);

has 'prod_server' => (
    is      => 'ro',
    isa     => 'Str',
    default => 'ics2ws.ic3.com',

);

has 'cybs_version' => (
    is      => 'ro',
    isa     => 'Str',
    default => '1.26',
);

has 'wsse_nsuri' => (
    is  => 'ro',
    isa => 'Str',
    default =>
        'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd',
);

has 'wsse_prefix' => (
    is      => 'ro',
    isa     => 'Str',
    default => 'wsse',
);

has 'password_text' => (
    is  => 'ro',
    isa => 'Str',
    default =>
        'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText',
);

has 'refcode' => (
    is      => 'ro',
    isa     => 'Str',
    default => sub { return join( '', Time::HiRes::gettimeofday ) }
);

has 'agent' => (
    is      => 'ro',
    isa     => 'SOAP::Lite',
    lazy    => 1,
    builder => '_get_agent',
);

sub _get_agent {
    my $self = shift;
    return SOAP::Lite->uri( 'urn:schemas-cybersource-com:transaction-data-'
            . $self->cybs_version )
        ->proxy( 'https://'
            . ( $self->production ? $self->prod_server : $self->test_server )
            . '/commerce/1.x/transactionProcessor' )->autotype(0);
}

sub _get_response {
    my $self = shift;
    return Checkout::CyberSource::SOAP::Response->new;
}

sub addField {
    my ( $self, $parentRef, $name, $val ) = @_;
    push( @$parentRef, SOAP::Data->name( $name => $val ) );
}

sub addComplexType {
    my ( $self, $parentRef, $name, $complexTypeRef ) = @_;
    $self->addField( $parentRef, $name,
        \SOAP::Data->value(@$complexTypeRef) );
}

sub addItem {
    my ( $self, $parentRef, $index, $itemRef ) = @_;
    my %attr;
    push( @$parentRef,
        SOAP::Data->name( item => \SOAP::Data->value(@$itemRef) )
            ->attr( { ' id' => $index } ) );
}

sub addService {
    my ( $self, $parentRef, $name, $serviceRef, $run ) = @_;
    push( @$parentRef,
        SOAP::Data->name( $name => \SOAP::Data->value(@$serviceRef) )
            ->attr( { run => $run } ) );
}

sub formSOAPHeader {
    my $self = shift;
    my %tokenHash;
    $tokenHash{Username}
        = SOAP::Data->type( '' => $self->id )->prefix( $self->wsse_prefix );
    $tokenHash{Password}
        = SOAP::Data->type( '' => $self->key )
        ->attr( { 'Type' => $self->password_text } )
        ->prefix( $self->wsse_prefix );

    my $usernameToken = SOAP::Data->name( 'UsernameToken' => {%tokenHash} )
        ->prefix( $self->wsse_prefix );

    my $header
        = SOAP::Header->name( Security =>
            { UsernameToken => SOAP::Data->type( '' => $usernameToken ) } )
        ->uri( $self->wsse_nsuri )->prefix( $self->wsse_prefix );

    return $header;
}

sub checkout {
    my ( $self, $args ) = @_;
    my $refcode = $self->refcode;
    my $header = $self->formSOAPHeader();
    my @request;

    $self->addField( \@request, 'merchantID',            $self->id );
    $self->addField( \@request, 'merchantReferenceCode', $refcode );
    $self->addField( \@request, 'clientLibrary',         'Perl' );
    $self->addField( \@request, 'clientLibraryVersion',  "$]" );
    $self->addField( \@request, 'clientEnvironment',     "$^O" );

    my @billTo;
    $self->addField( \@billTo, $_, $args->{ $self->column_map->{$_} } )
        for
        qw/firstName lastName street1 city state postalCode country email ipAddress/;
    $self->addComplexType( \@request, 'billTo', \@billTo );

    my @item;
    $self->addField( \@item, $_, $args->{ $self->column_map->{$_} } )
        for qw/unitPrice quantity/;
    $self->addItem( \@request, '0', \@item );

    my @purchaseTotals;
    $self->addField( \@purchaseTotals, 'currency',
        $args->{ $self->column_map->{currency} } );
    $self->addComplexType( \@request, 'purchaseTotals', \@purchaseTotals );

    my @card;
    $self->addField( \@card, $_, $args->{ $self->column_map->{$_} } )
        for qw/accountNumber expirationMonth expirationYear/;
    $self->addComplexType( \@request, 'card', \@card );

    my @ccAuthService;
    $self->addService( \@request, 'ccAuthService', \@ccAuthService, 'true' );
    my $reply = $self->agent->call( 'requestMessage' => @request, $header );
    return $self->response->respond( $reply, { refcode => $refcode, %{$args} }, $self->column_map );
}

__PACKAGE__->meta->make_immutable;

1;

# ABSTRACT: A Modern Perl interface to CyberSource's SOAP API


__END__
=pod

=head1 NAME

Checkout::CyberSource::SOAP - A Modern Perl interface to CyberSource's SOAP API

=head1 VERSION

version 0.08

=head1 SYNOPSIS

This is for single transactions of variable quantity.

B<column_map> is important. You B<must> map the keys in the hashref you send
(which also sets the keys for the payment_info hashref you receive back).
CyberSource uses camelCased and otherwise idiosyncratic identifiers here, so
this mapping cannot be avoided.

I mentioned above that this module does not store credit card numbers; more
specifically, the payment_info hash that the Response object returns deletes
the credit card number, replaces it with card_type, and adds 4 additional keys:

    decision fault reasoncode refcode

These are for more a detailed record of why a particular transaction was denied.

=head2 Standalone Usage

You can use this as a standalone module by sending it a payment information
hashref. You will receive a Checkout::CyberSource::SOAP::Response object
containing either a success message or an error message. If successful, you
will also receive a payment_info hashref, suitable for storing in your
database.

    my $checkout = Checkout::CyberSource::SOAP->new(
        id         => $id,
        key        => $key,
        column_map => $column_map
    );

    ...

    my $response = $checkout->checkout($args);

    ...

    if ($response->success) {
        my $payment_info = $response->payment_info;
        # Store payment_info in your database, etc.
    }
    else {
        # Display error message
        print $response->error->{message};
    }

=head2 Catalyst

You can use this in a Catalyst application by using L<Catalyst::Model::Adaptor>
and setting your configuration file somewhat like this:

    <Model::Checkout>
        class   Checkout::CyberSource::SOAP
        <args>
            id  your_cybersource_id
            key your cybersource_key
            #production  1
            <column_map>
                firstName		firstname
                lastName		lastname
                street1		    address1
                city    		city
                state	    	state
                postalCode	    zip
                country         country
                email           email
                ipAddress		ip
                unitPrice		amount
                quantity		quantity
                currency		currency
                accountNumber	cardnumber
                expirationMonth	expiry.month
                expirationYear	expiry.year
            </column_map>
        </args>
    </Model::Checkout>

production is commented out. You will want to set production to true when you
are ready to process real transactions. So that in your payment processing
controller you would get validated data back from a shopping cart or other
form and do something like this:

    # If your checkout form is valid, call Checkout::CyberSource::SOAP's
    # checkout method:

    my $response = $c->model('Checkout')->checkout( $c->req->params );

    # Check the Checkout::CyberSource::SOAP::Response object, branch
    # accordingly.

    if ( $response->success ) {

        # Store a payment in your database

        my $payment = $c->model('Payment')->create($response->payment_info);

        $c->flash( status_msg => $response->success->{message} );
        $c->res->redirect($c->uri_for('I_got_your_money'));
    }

    else {
        $c->stash( error_msg => $response->error->{message} );
        return;
    }

=head1 METHODS

=head2 item checkout

The only method you need to call.

=head2 addComplexType

Internal method for construction of the SOAP object.

=head2 addField

Internal method for construction of the SOAP object.

=head2 addItem

Internal method for construction of the SOAP object.

=head2 addService

Internal method for construction of the SOAP object.

=head2 formSOAPHeader

Internal method for construction of the SOAP object.

=head1 ATTRIBUTES

=head2 refcode

Reader: refcode

Type: Str

This documentation was automatically generated.

=head2 wsse_nsuri

Reader: wsse_nsuri

Type: Str

This documentation was automatically generated.

=head2 key

Reader: key

Type: Str

This documentation was automatically generated.

=head2 production

Reader: production

Type: Bool

This documentation was automatically generated.

=head2 wsse_prefix

Reader: wsse_prefix

Type: Str

This documentation was automatically generated.

=head2 id

Reader: id

Type: Str

This documentation was automatically generated.

=head2 password_text

Reader: password_text

Type: Str

This documentation was automatically generated.

=head2 response

Reader: response

Writer: response

Type: Checkout::CyberSource::SOAP::Response

This documentation was automatically generated.

=head2 column_map

Reader: column_map

Type: HashRef

This attribute is required.

This documentation was automatically generated.

=head2 cybs_version

Reader: cybs_version

Type: Str

This documentation was automatically generated.

=head2 prod_server

Reader: prod_server

Type: Str

This documentation was automatically generated.

=head2 test_server

Reader: test_server

Type: Str

This documentation was automatically generated.

=head2 agent

Reader: agent

Type: SOAP::Lite

This documentation was automatically generated.

=head1 METHODS

=head2 wsse_nsuri

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 addItem

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 key

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 id

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 new

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 addField

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 addComplexType

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 column_map

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 prod_server

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 cybs_version

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 refcode

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 production

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 wsse_prefix

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 addService

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 password_text

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 response

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 formSOAPHeader

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 checkout

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 test_server

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head2 agent

Method originates in Checkout::CyberSource::SOAP.

This documentation was automaticaly generated.

=head1 WHY?

Folks often have a need for simple and quick, but "enterprise-level" payment-
gateway integration. CyberSource's Simple Order API still requires that you
compile a binary, and it won't compile on 64-bit processors (no, not OSes, but
processors, i.e., what I imagine to be most development workstations by now).
So you have to use the SOAP API, which is unwieldy, not least because it uses
XML. May no one struggle with this again.  :)

=head1 NOTICE

=head2 Credit Card Numbers

To save you some legal hassles and vulnerability, this module does not store
credit card numbers. If you'd like the option of returning a credit card
number from the Response object, please send a patch.

=head2 ID and Key

Please note that you B<must> use your own CyberSource id and key, even for
testing purposes on CyberSource's test server. This module defaults to
using the test server, so when you go into production, set production to
a true value in your configuration file or in your object construction, e.g.,

    my $checkout = Checkout::CyberSource::SOAP->new(
        id         => $id,
        key        => $key,
        production => 1,
        column_map => $column_map
    );

=head1 CONTRIBUTORS

Tomas Doran (t0m) E<lt>bobtfish@bobtfish.netE<gt>
Caleb Cushing (xenoterracide) E<lt>xenoterracide@gmail.comE<gt>

=head1 SEE ALSO

L<Catalyst::Model::Adaptor> L<Business::OnlinePayment::CyberSource>

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website
https://github.com/amiri/Checkout--CyberSource--SOAP/issues

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

Amiri Barksdale <amiri@arisdottle.net>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Amiri Barksdale.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

