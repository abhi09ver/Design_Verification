# APB agent infrastructure

*Chapter: APB agent · source: attached*

Hi, my name is Christian Slav and in this tutorial we are going to talk about app agent infrastructure.
This is the picture of what we implemented so far in our project.
We have a Testbench and inside the testbench we have the test and the instance of the dot and inside the test we have currently an empty environment.
Our next focus is to implement the app agent, but in this tutorial we will only implement the basic infrastructure of this agent, which is the agent class, the interface and the configuration component, and the interface is used by the agent to communicate with the aligner.
To make things clearer, let's redraw this image by omitting those components which will be later implemented in our environment.
The image now looks like this.
Our environment only contains the app agent with the configuration component and the interface.
However, this representation is not really accurate with what we will implement in the code.
This is because in reality the interface will be instantiated inside the Testbench.
This is because a Systemverilog interface, when you create an instance of it that is fixed is like static.
You cannot create on the fly interfaces, and this is why an interface cannot be created inside an Systemverilog class, which is our agent.
But we need to have access to this interface inside our app agent.
So we need to pass a pointer of this interface inside our agent, and we do this via the UVM configuration database.
This database is nothing more than a systemverilog class uvm config db which has a parameter.
The parameter is the type of data that you want to put in the database and to put some information in the database, you have the set function and we will put a pointer to our interface.
So this will be a virtual interface.
And then from our agent we will get that pointer from the database using the get function.
Let's first discuss the set function.
Its signature is this one.
It has four arguments and the last one the value represents the value that you want to put in the database.
But when you are doing this, you are actually putting in the database a key value pair.
And the key is represented by this field name argument which is of type string.
So you want to associate a name to the value that you want to put in the database.
The first two arguments, context and instance name, are used to identify which component you want to have access to.
The value that you are putting in the database.
And these are strongly connected to the name you use when you created the instance of each component.
So for example, when we created the environment in the create function we used as the name env.
And we also specify the parent this.
So now UVM knows that our instance of the environment has the name env.
We did the same thing.
Also for the app agent we specify its name to be app underscore agent for the test.
Remember that I told you that all the tests will have the name UVM test for each component in the UVM library has this function called Get full name.
And what this function does, it's actually is returning a string with all those names concatenated.
So the get full name function of our app agent will return something like this UVM test top dot env dot app agent.
Let's look at some examples of how this function set can be called.
Let's say that we want to pass to the app agent a key value pair made out of these two a bus width and value 32.
If we call this function from the testbench, then we specify as the context null because the Testbench is not an UVM component, it's a Verilog module and the instance name.
It will be the full name of the app agent UVM desktop dot env dot app agent.
We can also call the set function from the test, and in this case we can use as the context.
This because test is already an UVM component and instance name.
It will be the full name of our app agent relative to the test, so it will be env dot apb agent.
Of course if we call this from the environment, then the context, this is the environment.
And then the full name of our app agent relative to the environment is just app agent.
The set function also supports the star notation.
So if we call the set function in this manner with UVM desktop dot star, then we are actually saying that we want all the components under the test to have access to this path width equals to 32.
You must pay close attention to this set function, because there is a catch when you call the set function from multiple levels.
So for example, let's say that we call the set function with this bus width from the test bench and we pass the value 32.
And also from our test in which we want to set this to 64, the question is what value it will be returned when we get this bus width from the APB agent.
And this depends on the moment when you are doing that get.
So if you are doing that get when the environment is built, the return value will be the one which is put in the database by the component with the highest context in this hierarchy.
So in this case it will be the testbench.
But if you do this get when you are in the run phase, the return value will be the last one put in the database.
And this is explained in the UVM class reference manual in this paragraph.
So I'll let you read this text carefully.
Just pay attention to it because it might cause you to lose a lot of debug time.
The get function is quite similar to the set.
It has almost the same arguments context, instance, name, field name, and value.
The difference here is the value argument.
It's an inout.
So this means that whatever you want to retrieve from the database will be placed in this value argument.
And also the get function now returns a bit, so it will return one if the get was successful, or zero if it wasn't.
An example of how this get function is called in the app agent is this one.
We will use as the context this and as instance name.
It will be only an empty string because we already are in the app agent filename.
It will be the same bus width and the value.
It will be a field inside the app agent in which we want to place the value of this bus width.
That's about it.
Let's recap.
We talked about the app agent infrastructure and how the interface is passed to the agent.
We talked about the UVM configuration database and its two main functions set and get.
In the next tutorial we will implement all this stuff together.
Thanks for watching and see you in the next tutorial.
Bye!
