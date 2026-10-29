# MD agent architecture

*Chapter: MD agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to talk about the EMD agent architecture.
Our goal is to build this EMD agent but with two aspects.
One which will be connected to the air interface, and this one will be a master agent.
And it is called a master because it is the one which starts the EMD transaction.
So it's pushing data on this air interface.
The other aspect is the slave agent, and we call it a slave, because it is the one which is receiving and responding to the transactions started by our RTL.
So the tax agent will only respond with those radian error signals.
And as you can imagine, there will be a lot of classes which will have a common implementation for the master and the slave aspects.
So let's quickly go through all the classes of the agent and see which of those classes will have to have particular implementation for the master and for the slave aspect.
The first group of classes that we have to build is the ones which model the item and we will create.
As for the APB agent, this item base class and from this one we will create two subclasses, one for the monitor and one for the driver.
The monitor will be common to both of these aspects, to the master and to the slave, but the driver part will have to be split in two.
There will be some information which is required for the slave driver and other information which is required for the master driver.
And this is why we split this in two.
Next let's look at the interface and this one will be common.
Let's paint it in green.
So we will have the same interface defined for both of these aspects.
One important thing to mention here is that our MD interface will have a parameter called data width to control the width in bits of the data bus.
Remember, in the APB agent, we used a define to declare the width of the data.
But the define approach is easier, but it's less flexible than working with a parameter.
And with this MD agent, we will see what is required for us to build a more flexible agent by working with a parameter as the data width.
Also, the monitor class will be common to both of these agents, as the monitor only looks on the bus to collect the transactions, and this is an identical process regardless if we look on the master or the slave interface.
And because the monitor is common, and also the coverage class will be common as the coverage only gets information from the monitor.
The sequencer class also is common to both of these agents, as the sequencer has nothing to do with some master or slave implementation.
The first difference for these two agents is for the driver, where we will build a common driver class inheriting from UVM driver, and then we will split this class into slave and master subclasses.
In the common MD driver class, we will declare all the tasks required for the driver, and also we will handle the reset logic between the slave and master classes.
We will actually build the logic to drive for the master the axis.
So this will drive the.
That valid data size and offset signals.
And then in the slave driver we will drive that ready and error signals.
And also the agent configuration class will require two aspects for the slave and for the master.
And this is because we might need some different configurations for these two agents.
For example, in the slave agent configuration class, we might want to mention the reset value of the ready signal.
And finally, the agent class will have to be split in two in order to instantiate different classes for the agent configuration class and for the driver.
And of course, the agent will have to have a parameter for the data width.
In order to know with what kind of interface the agent must work with.
So that's it for this tutorial.
We quickly went through all the classes, which will be part of the MD Agent architecture, and starting with the next tutorial we will implement those classes together.
Thanks for watching and see you in the next tutorial.
