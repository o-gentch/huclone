require "test_helper"

class Knowledge::ClustererTest < ActiveSupport::TestCase
  test "separates obvious clusters" do
    vectors = (0...6).map { |i| cluster_vector(0, i) } + (0...6).map { |i| cluster_vector(1, i) }
    groups = Knowledge::Clusterer.call(vectors, 2)
    assert_equal 2, groups.size
    assert_equal [ (0...6).to_a, (6...12).to_a ], groups.map(&:sort).sort_by(&:first)
  end

  test "handles degenerate input" do
    assert_equal [ [ 0 ] ], Knowledge::Clusterer.call([ cluster_vector(0) ], 3)
    assert_equal [ [ 0, 1 ] ], Knowledge::Clusterer.call([ cluster_vector(0), cluster_vector(0) ], 1)
    dup = Array.new(5) { cluster_vector(0) }
    assert_equal 5, Knowledge::Clusterer.call(dup, 3).flatten.size
  end

  test "cosine and centroid" do
    assert_in_delta 1.0, Knowledge::Clusterer.cosine([ 1, 0 ], [ 2, 0 ]), 1e-9
    assert_in_delta 0.0, Knowledge::Clusterer.cosine([ 1, 0 ], [ 0, 1 ]), 1e-9
    assert_equal 0.0, Knowledge::Clusterer.cosine(nil, [ 1 ])
  end
end
