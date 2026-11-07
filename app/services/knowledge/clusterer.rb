require "numo/narray"

module Knowledge
  # k-means (k-means++ инициализация) по косинусной близости на Numo.
  # Кластеризуются не чанки, а резюме фрагментов — сотни точек, а не тысячи.
  module Clusterer
    ITERATIONS = 25

    module_function

    # vectors: Array<Array<Float>>; возвращает Array<Array<Integer>> — индексы по кластерам
    def call(vectors, k, seed: 42)
      n = vectors.size
      return [ (0...n).to_a ] if k <= 1 || n <= 1
      return (0...n).map { |i| [ i ] } if n <= k

      x = normalize(Numo::DFloat.cast(vectors))
      rng = Random.new(seed)
      centers = init_centers(x, k, rng)
      k = centers.shape[0] # при дубликатах точек центров может быть меньше
      assign = nil

      ITERATIONS.times do
        sims = x.dot(centers.transpose)            # n × k
        new_assign = (0...n).map { |i| sims[i, true].max_index }
        break if new_assign == assign
        assign = new_assign
        k.times do |c|
          members = assign.each_index.select { |i| assign[i] == c }
          next if members.empty?
          centers[c, true] = normalize(x[members, true].mean(axis: 0).reshape(1, true))[0, true]
        end
      end

      clusters = Array.new(k) { [] }
      assign.each_with_index { |c, i| clusters[c] << i }
      clusters.reject(&:empty?)
    end

    def centroid(vectors)
      return nil if vectors.empty?
      normalize(Numo::DFloat.cast(vectors).mean(axis: 0).reshape(1, true))[0, true].to_a
    end

    def cosine(a, b)
      return 0.0 if a.nil? || b.nil?
      x = Numo::DFloat.cast(a)
      y = Numo::DFloat.cast(b)
      denom = Math.sqrt(x.dot(x)) * Math.sqrt(y.dot(y))
      denom.zero? ? 0.0 : x.dot(y) / denom
    end

    def normalize(m)
      norms = Numo::NMath.sqrt((m * m).sum(axis: 1)).reshape(m.shape[0], 1)
      norms[norms.eq(0)] = 1.0
      m / norms
    end

    def init_centers(x, k, rng)
      n = x.shape[0]
      chosen = [ rng.rand(n) ]
      while chosen.size < k
        sims = x.dot(x[chosen, true].transpose)    # n × |chosen|
        dist = (0...n).map { |i| 1.0 - sims[i, true].max }
        dist = dist.map { |d| [ d, 0 ].max**2 }
        total = dist.sum
        break if total.zero?
        r = rng.rand * total
        acc = 0.0
        pick = dist.each_index.find { |i| (acc += dist[i]) >= r } || (n - 1)
        chosen << pick unless chosen.include?(pick)
      end
      x[chosen, true].dup
    end
  end
end
