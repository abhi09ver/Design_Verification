# MD agent infrastructure

*Chapter: MD agent · source: attached*

Hi, my name is Christiane Slav and in this tutorial we are going to talk about the EMD agent infrastructure.
This is the current image of our environment and in this tutorial we want to develop these parts.
So we want to create the ADCs and takes agents of the master and the slave.
And inside we want to create the agent configuration class and also the interface.
So let's see how we can do this.
Let's make some room for some code snippets here.
First let's discuss the interface.
So it will be the same interface for the master and the slave agent.
And simply we have to declare an interface called CFS Mdif.
And the difference between this interface and the one from the APB agent is that in this one, we will use the data width as a parameter in order to control the width of the data signal.
And in here we will declare all the signals part of the EMD The interface.
Next we have to create in the Testbench two instances of this interface, one for the ADC side and one for the text side.
And in this version of the RTL, both of them will have the data with parameter equal to 32.
After that, we need to connect all the signals of our duty to the appropriate interface, so all the signals with matrix will be connected to the signals part of the matrix interface, and the same for the takes.
All the signals starting with MDT will be connected to our MDT interface.
And finally we need to put these two interfaces in the UVM config database.
And we need to pay attention when we do this because both of these interfaces, the ADC and the tax will be put in the database with exactly the same name VIF, because the agent inside.
When we code the logic to get the interface, we are not aware if the agent will be a master or a slave.
So we only get the interface with this name.
But in here in the testbench, we ensure that we put the MDX interface exactly to the MDX agent by specifying here its full name and the same for the take.
So this is how the instances of those two agents will know to pick up from the database the correct interface assigned to it.
Next, the agent configuration class will have a base class called CFS named agent Config, which also will have this data width as a parameter because it is working with the virtual interface.
And then it will have mostly the same fields as the ones which we declared in the APB agent.
So it will be a lot of copy paste here, but we want the agent configuration class to have specific subclasses for the slave agent and for the master agent.
And currently we will leave these classes empty.
We will not declare any fields here.
We will add some fields when we need them later in our tutorials.
And finally we will have to declare the agent class called CFS, MD agent.
And in here we will declare the handler to the agent config.
And even though we created two subclasses for the agent config for the master and the slave in here in the base class of the agent, we will declare the agent config of type cfs, MD agent config.
And also we will create the instance for this agent config class.
So in the build phase we will create this agent config using the create function like so.
But what we want is to have two subclasses of the agent, one for the slave and one for the master.
And in each of those we want to have a specific type of agent config.
So in the slave we want to have that agent config slave.
And also in the master we want to have that agent config master.
So how do we accomplish this.
How do we change this agent config to be of type.
For example agent config master in the master not of this type.
And UVM provides a very interesting mechanism to do this, and it is applying the factory design pattern.
And what this means is that in the specific agent master class you can do something like this.
You can specify that you want to replace any instance of type agent config with something that you want.
For example agent config master, and we can accomplish this using this function from the type id set inst override.
And this means that you want to override the type of the instance which was agent config.
So this one with agent config master and you can be very specific which instances you want to override in this function set instance override.
You can specify um that this override should happen only under this uh component here, and only for the instances of this name agent config, because we want this override to happen only in the master.
So this is why we use this set instance override.
So what this does it will force this create function to return here not an instance of the agent config of type agent config, but of type agent config master and we can do the same thing for the slave.
So in the agent slave class, we want to say that we want to replace the instance of the agent config with one of type agent config slave.
And also we want to make sure that this override only affects the slave.
So we use here the third parameter to be this.
And we want to specify that this override should happen only for the instances with this name agent config.
So this one from here should match this one from here.
And of course in order for this set instance override to have an effect, it is mandatory that you call this set instance override before the call to the create function is performed.
Otherwise it will have no effect.
When create function is called, it will not know that you want to override any instance.
So this is why we set this set instance override in the constructor of the agent, because we know that the constructor will be called before the build phase.
So this override mechanism and the factory, it's a very important part of the UVM library.
This factory design pattern allows a lot of reusability in your code.
If you use it carefully.
I strongly recommend you to read more on this mechanism.
And the first place to look is in the UVM User Guide under this chapter Advanced Topics.
There is this.
Chapter 6.2 the Built in Factory and overrides.
It's just a few pages.
I think there are only three pages, but you can get a lot of information from here about how the factory works.
It will explain here some important aspects like why we use the create function and not directly the constructor, because through this create function, the factory can replace the instance that it will return to you.
And also, I think just a little bit down below, it will give you some information about why it is so important to use those macros.
UVM object utils and uvm component utils.
These macros are crucial for the factory design pattern, because it will inject in the classes that you declare some code, which will enable this override to work.
And of course another source of information for you.
It will be the UVM class reference.
And in here you can find, for example some description on that set instance override function in here in factory classes and under here UVM registry.
You can find for the UVM component registry class for example, this function that we will use set instance overwrite and you can read here its short description to understand better what all these parameters are doing.
So my recommendation to you is to spend some five ten minutes to go through this chapter.
The built in factory and overrides.
It's a very short one.
I think there are only something like three pages.
You can quickly go through them and get a very good understanding about how this mechanism works.
That's it.
For this tutorial we talked about the MDE agent infrastructure and most important, how we will pass the interfaces from the Testbench to the agents.
And we talked about the UVM class override, which is a very important part of the UVM library.
In the next tutorial we will implement all this together in the code.
Thanks for watching and see you in the next tutorial.
