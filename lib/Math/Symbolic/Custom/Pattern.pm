package Math::Symbolic::Custom::Pattern;

use 5.006001;
use strict;
use warnings;
no warnings 'recursion';
use Carp qw/cluck confess/;

use Clone qw/clone/;
use Math::Symbolic qw/:all/;
use Math::Symbolic::Custom::Pattern::Export;

our $VERSION = '1.02';

use constant EPSILON => 1e-29;

use constant {
	TYPE => 0,
	VAL => 1,
	OPS => 2,
};

use constant PATTERN => -1;

use constant {
	ANY_TREE    => 0,
	ANY_CONST   => 1,
	ANY_VAR     => 2,
	NAMED_TREE  => 3,
	NAMED_CONST => 4,
	NAMED_VAR   => 5,
};

=head1 NAME

Math::Symbolic::Custom::Pattern - Pattern matching on Math::Symbolic trees

=head1 SYNOPSIS

  use Math::Symbolic qw/parse_from_string/;
  use Math::Symbolic::Custom::Pattern;
  my $patternstring = "VAR_foo + sin(CONST * VAR_foo)"
  my $pattern = Math::Symbolic::Custom::Pattern( $patternstring );
  
  my $formula = parse_from_string("a + sin(5 * a)");
  
  if ($pattern->match($formula)) {
    print "The pattern matches the formula.\n";
  }
  else {
    print "The pattern does not match the formula.\n";
  }

  # will print "The pattern matches the formula" since "a" is
  # found to be "VAR_foo" and 5 is a constant.
  # "a + sin(5 * b)" would not match since VAR_foo is already "a"
  # when the "b" is encountered. "VAR" would match any variable.
  # "TREE" matches any tree. "TREE_name" and "CONST_name" work as
  # you would expect.
  
  # Alternatively:
  my $pattern = $some_formula->to_pattern();
  
  print "yes" if $formula->is_of_form($pattern); # fast-ish
  # This has syntactic sugar, too:
  print "yes" if $formula->is_of_form("VAR + TREE"); # slow!
  print "yes" if $formula->is_of_form($another_formula); # semi-slow...

=head1 DESCRIPTION

This module is an extension to the Math::Symbolic module. A basic
familiarity with that module is required. 

The Math::Symbolic::Custom::Pattern module implements pattern matching routines
on Math::Symbolic trees. The patterns itself are constructed from Math::Symbolic
trees with just a few variables which have a special meaning.

The module provides two interfaces. You can use the C<new()> and C<match()>
methods this class provides, or you can use the C<to_pattern()> and
C<is_of_form()> methods on any Math::Symbolic tree. (Exported by the
Math::Symbolic::Custom::Pattern::Export module. Refer to that module for
details on C<is_of_form()>.)

You can construct a pattern from any Math::Symbolic tree. For sake of
simplicity, we will talk about a tree "a+(b*c)" even if that's just its string
representation. The tree is really what is returned by
C<Math::Symbolic-E<gt>parse_from_string("a+(b*c)")>.

Suppose you call

  my $pattern = Math::Symbolic::Custom::Pattern->new("a+(b*c)");

That creates a pattern that matches this exact tree. Calling

  my $boolean = $pattern->match($tree);

on any Math::Symbolic tree C<$tree> will result in C<$boolean> being false
except if it is C<"a+(b*c)">.

So far so good. This isn't impressive and the C<is_identical()> method of
all Math::Symbolic trees does the same. (Except that the pattern matching is
about twice as fast.)

If you create a pattern from the following string, however, you get different
behaviour: C<"VAR + (VAR*VAR)">. Now, any variable may be in place of C<a>,
C<b>, and C<c>. (C<"a + (x*x)">, C<b + (b*b)>, ...)

You can match with named (but not literal) variables with the following
pattern string: C<"VAR_first + (VAR_first*VAR_second)"> This matches
the tree C<"a + (a*b)">, but not C<"a + (c*b)"> since the first variable
in the parenthesis of the second tree is not the same as the one outside the
parenthesis. Note that the variable C<"b"> in both examples could have been
any variable, since C<VAR_second> occurrs only once in the pattern.

Analogous to the general C<VAR> and named C<VAR_foo> pattern elements, you may
use C<TREE> to match any subtree whatsoever or C<TREE_foo> to match a named
tree. Example: The pattern C<"TREE_a + 5*TREE_a"> matches the tree
C<"sin(b+c) + 5*sin(b+c)">, but not C<"sin(b+c) + 5*cos(b+c)">. Beware of the
fact that the trees C<"sin(b+c)"> and C<"sin(c+b)"> would not be the same
either. Though mathematically equivalent, they do not have the same internal
representation. Canonicalizing the internal representation is simple in this
example, but is impossible in the general case, so just take care.

Finally, what works with variables and general trees also works with constants.
You may specify the pattern C<"CONST_foo * a + atan(CONST_foo)">. This matches
C<"0.5*a + atan(0.5)">, but does not match C<"2*a + atan(0.5)"> since the
named constants are not equal. The general form C<CONST> works as a wildcard
for any constants.

=head2 EXPORT

This module does not export anything.

=head2 METHODS

This is a list ofpublic methods.

=over 2

=cut


=item new

C<new()> is the constructor for Math::Symbolic::Custom::Pattern objects.
It takes a Math::Symbolic tree as first argument which will be transformed
into a pattern. See the C<match()> method documentation.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto)||$proto;

	# I want to call that 'proto', too ;)
	$proto = shift;
	confess(
		__PACKAGE__."new() requires a Math::Symbolic tree as first "
		."argument."
	) if not ref($proto) =~ /^Math::Symbolic/;

	my $info = {
		vars => {},
		constants => {},
		trees => {},
	};
	
	my $pattern = _descend_build($proto, $info);

	#_descend_generalize($pattern, $info);

	my $self = {
		pattern => $pattern,
		info => $info,
	};

	return bless $self => $class;
}


sub _descend_build {
	my ($proto, $info) = @_;
	
	my $tree = [];
	my $tt = $proto->term_type();

	if ($tt == T_CONSTANT) {
		$tree->[TYPE] = T_CONSTANT;
		$tree->[VAL] = $proto->value();
	}
	elsif ($tt == T_OPERATOR) {
		$tree->[TYPE] = T_OPERATOR;
		$tree->[VAL] = $proto->type();
		$tree->[OPS] = [
			map { _descend_build($_, $info) }
			@{$proto->{operands}}
		];
	}
	else {
		my $name = $proto->name();

		$tree->[TYPE] = PATTERN;
		if ($name eq 'TREE') {
			$tree->[VAL] = ANY_TREE;
		}
		elsif ($name eq 'CONST') {
			$tree->[VAL] = ANY_CONST;
		}
		elsif ($name eq 'VAR') {
			$tree->[VAL] = ANY_VAR;
		}
		elsif ($name =~ /^TREE_(\w+)$/) {
			$tree->[VAL] = NAMED_TREE;
			my @names = split /_/, $1;
			$tree->[OPS] = \@names;
			$info->{trees}{$_}++ for @names;
		}
		elsif ($name =~ /^CONST_(\w+)$/) {
			$tree->[VAL] = NAMED_CONST;
			my @names = split /_/, $1;
			$tree->[OPS] = \@names;
			$info->{constants}{$_}++ for @names;
		}
		elsif ($name =~ /^VAR_(\w+)$/) {
			$tree->[VAL] = NAMED_VAR;
			my @names = split /_/, $1;
			$tree->[OPS] = \@names;
			$info->{vars}{$_}++ for @names;
		}
		else {
			$tree->[TYPE] = T_VARIABLE;
			$tree->[VAL] = $name;
		}
	}

	return $tree;
}


=item match

This method takes a Math::Symbolic tree as first argument. It throws a
fatal error if this is not the case.

It returns a true value if the pattern matches the tree and a false value
if the pattern does not match. Please have a look at the L<DESCRIPTION>
to find out what I<matching> means in this context.

=cut


sub match {
	my $self = shift;

	my $tree = shift;
	confess(
		__PACKAGE__."match() requires a Math::Symbolic tree as first "
		."argument."
	) if not ref($tree) =~ /^Math::Symbolic/;

	my $info = $self->{info};
	my $info_copy = {
		constants => { map {($_,undef)} keys %{$info->{constants}} },
		vars => { map {($_,undef)} keys %{$info->{vars}} },
		trees => { map {($_,undef)} keys %{$info->{trees}} },
	};
	
	my $okay = _descend_match($self->{pattern}, $tree, $info_copy);
	return $okay;
}

sub _descend_match {
	my ($pat, $tree, $info) = @_;
	
	my $ptype = $pat->[TYPE];
	my $ttype = $tree->term_type();

	if ($ptype == T_CONSTANT) {
		return undef if $ttype != T_CONSTANT;
		return 1 if abs($tree->value()-$pat->[VAL]) < EPSILON;
		return undef;
	}
	elsif ($ptype == T_VARIABLE) {
		return undef if $ttype != T_VARIABLE;
		return 1 if $tree->name() eq $pat->[VAL];
		return undef;
	}
	elsif ($ptype == T_OPERATOR) {
		return undef if $ttype != T_OPERATOR;
		my $optype = $tree->type();
		return undef if $optype != $pat->[VAL];
		
		my @operands = @{$pat->[OPS]};
		my @tree_ops = @{$tree->{operands}};

		return undef if @operands != @tree_ops;
		
		foreach (0..$#operands) {
			my $ok = _descend_match($operands[$_], $tree_ops[$_], $info);
			return undef unless $ok;
		}
		return 1;
	}
	elsif ($ptype == PATTERN) {
		my $match = $pat->[VAL];
		if ($match == ANY_TREE) {
			return 1;
		}
		elsif ($match == ANY_CONST) {
			my $ttype = $tree->term_type();
			return $ttype == T_CONSTANT ? 1 : undef;
		}
		elsif ($match == ANY_VAR) {
			my $ttype = $tree->term_type();
			return $ttype == T_VARIABLE ? 1 : undef;
		}
		elsif ($match == NAMED_TREE) {
			my @names = @{$pat->[OPS]};
			my $itrees = $info->{trees};
			foreach my $name (@names) {
				die "tree name '$name' should exist, but does not. "
					."Internal error."
				  if not exists $itrees->{$name};
				
				my $itree = $itrees->{$name};
				if (defined $itree) {
					my $ok = $itree->is_identical($tree);
					return 1 if $ok;
				}
				else {
					$itrees->{$name} = $tree;
					return 1;
				}
			}
			return undef;
		}
		elsif ($match == NAMED_CONST) {
			return undef unless $ttype == T_CONSTANT;
			
			my @names = @{$pat->[OPS]};
			my $iconsts = $info->{constants};
			foreach my $name (@names) {
				die "constant name '$name' should exist, but does not. "
					."Internal error."
				  if not exists $iconsts->{$name};
				
				my $iconst = $iconsts->{$name};
				if (defined $iconst) {
					my $ok = $iconst == $tree->value();
					return 1 if $ok;
				}
				else {
					$iconsts->{$name} = $tree->value();
					return 1;
				}
			}
			return undef;
		}
		elsif ($match == NAMED_VAR) {
			return undef unless $ttype == T_VARIABLE;
			
			my @names = @{$pat->[OPS]};
			my $ivars = $info->{vars};
			foreach my $name (@names) {
				die "variable name '$name' should exist, but does not. "
					."Internal error."
				  if not exists $ivars->{$name};
				
				my $ivar = $ivars->{$name};
				if (defined $ivar) {
					my $ok = $ivar eq $tree->name();
					return 1 if $ok;
				}
				else {
					$ivars->{$name} = $tree->name();
					return 1;
				}
			}
			return undef;
		}
		else {
			die "Internal error: Invalid pattern type '$match'";
		}
		
	}
	else {
		die "Invalid pattern type with number $ptype.";
	}
}



=begin comment

If completed, this could remove all placeholders that exist only once
and replace them with the more general match.
But I'll skip this since we might be able to combine patterns later.

sub _descend_generalize {
	my ($pattern, $info) = @_;
	
	my $type = $pattern->[TYPE];
	return if $type != PATTERN;

	my $ptype = $pattern->[VAL];

	if ($ptype == NAMED_TREE) {
		my @names = $pattern->[OPS];
		my $no_one = grep { $info->{trees}{$_} == 1 } @names;
		if ($no_one == @names) {
			# all of them exist only once
			
		}
		
	}
	elsif ($ptype == NAMED_CONST) {
	}
	
	
}

=end comment

=cut


1;
__END__

=back

=head1 SEE ALSO

New versions of this module can be found on http://steffen-mueller.net or CPAN.

L<Math::Symbolic::Custom::Pattern::Export> implements the C<is_of_form()>
and C<to_pattern()> methods.

L<Math::Symbolic>

L<Math::Symbolic::Custom> and L<Math::Symbolic::Custom::Base> for details on
enhancing Math::Symbolic.

=head1 AUTHOR

Steffen M�ller, E<lt>symbolic-module at steffen-mueller dot netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Steffen M�ller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.4 or,
at your option, any later version of Perl 5 you may have available.


=cut
