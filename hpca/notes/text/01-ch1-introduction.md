# Lecture notes: 01-ch1-introduction (text copy)

Searchable text extracted from [`../pdf/01-ch1-introduction.pdf`](../pdf/01-ch1-introduction.pdf). Diagrams and handwriting are only in the PDF.

```text
HPCA Chapter1
13 March 2025  20:56
This is CS6290 HPCA at Georgia Tech. In this course we will look at how modern processor cores work, how
they access memory, and how we put them together in a multicore chip. Before that let's see what is
computer architecture.
Vid2: What is computer architecture? It's designing computer something that's well suited for its purpose.
Vid3: Why do we need computer architecture?
  1. To improve performance (for whatever definition of performance like speed, battery life, size, weight,
  energy efficiency etc.)
  2. To improve some abilities of the computer.( like adding 3d Graphics support, adding debugging support,
  improving security etc.)
  Point1 is about making computers faster smaller and cheaper, whereas point 2 is about addition of
  features
  We do these with advancements in computer fabrication technology, and in Circuit design.
  Computer architecture is about using these two advancements to design faster, smaller, cheaper, more
  secure, energy efficient computers.
Vid 4 and 5 are a short quiz.
Vid 6 : If we design our computer with current technology and parts, by the time we complete our design, we
would have an obsolete computer. The fabrication technologies are so fast moving that we need to anticipate
the future technology and design for that. How do we anticipate, one trend is Moore's law.
Vid 7 : Moore's law says, Every 18-24 months feature size reduces by half, i.e 2x number of transistors on
same area. What does this imply to computer architects? We need to have energy per operation, processor
speed, memory capacity double every 18-24 months. This law has been in action since 1971 to 2007( until the
lecture year).
Vid 8 & 9 are speed doubling quiz.
Vid 10 : Memory wall : While the instructions/cycle and memory capacity has been doubling every 18-24
months, memory latency is just increasing at a pace of 1.1x every two years. This problem of memory speed
not matching up with the processor speed requirement is called Memory Wall.
To mitigate this issue we have been using caches as a sort of stairs for memory wall.
Vid 11 : When we talk about processor performance, we see about speed (number of instructions it can finish
in a second), its cost( for fabrication), and power(longer battery life and smaller form factor). With the
technological advancement, we can have speed, cost and power improve by 2x, 1x, 1x (or) 1.1x 0.5x, 0.5x
respectively we choose what to improve based on application.
Vid 12 : Relative merits of processor performance quiz : which of the following processor would give worst
laptop ?
Vid 13 : Crawlium and Burnium are extremes, but cost to performance and portability-wise some may want a
Crawlium type processor, but Burnium is irrational with respect to cost to performance ratio and portability
wise.
Model  Performance Battery life Weight Cost($)
Crawlium 0.1  30 Hrs.  12 g  10
Slowium 0.5  15  50  30
Laptium  1  5  100  100
Fastium  1.5  1  500  200
Hotium  2  15 min  1.5 Kg  500
Burnium 4  2 min  2 Kg  5000
Vid 14 : Power Consumption : there are two types of it , Dynamic and Static
Vid 15 : Active Power P = ½ C V2 f α
Capacitance is roughly proportional to chip area , alpha is activity factor. Say with the technology
improvement, we have half of the transistor size, so we choose to build twice as capable processor with two
cores using the same area as old, so the capacitance is same, now we want a better performance and lower
power in a chip (due to tech adv. its possible), so we choose to also increase the frequency by 25% and reduce
the voltage by 20 % , but the fact that with increase in frequency, for correct operation , we need to increase
the voltage also. With the technology improvement we will have transistor gate voltages to reduce, so we can
operate at same frequency at lower voltages. So with this advantage, we can reduce the voltage(say 90%) little
bit and increase the frequency little bit(say 1.1X) still get that transistor to operate properly . Hence overall
with 90% ( = 0.81*1.1) of the total power we are able to operate the chip at 1.1x frequency and double the
compute capacity.
Vid 16 : Static Power : We can plan to reduce the voltage much in order to reduce dynamic power, but what
stops us from doing that is leakage power. Which is also called static power. The optimal voltage is the one
that minimizes the total power consumption( static + dynamic ) .
Vid 17 : Active Power Quiz : If at 1V and 2 GHz, the power consumption is 30W. What is most power efficient
setting. And Power required for Highest performance.
  Voltage  0.9  1  1.1  1.2  1.3  1.4  1.5 V
  Frequency 1.8  2  2.2  2.4  2.6  2.8  3Ghz
Vid 18 : Most power efficient setting is the one with lowest freq and lowest voltage.
That is : 0.92/12 * 1.8 /2 * 30 = 21.9
  Powet consumption for most performance setting is 1.52 * 1.5 * 30 = 101.3
  As we can see there's a 5x higher power consumption for just ~50% improvement in performance. This
  is one of the main reason we go for multiple cores of lower frequency than one core of higher
  frequency?
Vid 19 & 20 : Fabrication Yield = Working chips / Total chips on a wafer, so for bigger chips we have bad yield
due to small manufacturing defects.
Vid 21 : Fabrication cost example : Let's say it costs $5000 to fabricate a wafer and cut it into chips. Number of
chips that can be produced from this wafer and costs for them are shown in table below, say there are 10
defects per wafer, and Chip cost = $5000/(# good chips per wafer)
  Name  Size  Cost
  Small  X(400 in a wafer) $5000/(400-10) =
  12.8
  Medium 4X (96 in wafer)  $5000/(96-10) =
  58.2
  Large  16X (20 in wafer) $5000/(20-10) =
  454.5
So as we can see as the area increases cost is not increasing in linear proportion, but its much higher.
So for every generation of new technology(halving of transistor size) , we have two choices 1. We make the
chip at smaller area, at much lower cost or 2. We produce another chip in same area, so we get twice as
powerful chip at same area and cost.
Vid 22 and 23 : Manufacturing cost Quiz, we have watch processor WP for 1mm^2, and we have Laptop
Processor LP for 100 mm ^2 .Now, cost of LP to cost of WP inequality is : cost(LP) ? 100*cost(WP). Answer is
cost of LP is more than 100* cost of WP due to lower yield
Vid 24 : Outro : As we have seen, Computer Architecture is about building computers that is better suited for
its purpose. In the coming parts of the course, we will learn about the techniques to improve computer's
performance, energy efficiency and cost. Before that we will see how to measure the performance and other
characteristics of computer designs. In other words we need to come up with numbers that express our
intuitive notion of better computers.
```
