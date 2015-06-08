###############################################################################
#   ESCAPADE
# Ergonomic Solver using Cellular Automata for PArtial Differential Equation
#       Copyright (C) 2009 Nicolas Fressengeas <nicolas@fressengeas.net>
#  Distributed under the terms of the GNU General Public License (GPL),
#  version 2 or any later version.  The full text of the GPL is available at:
#                  http://www.gnu.org/licenses/
###############################################################################

# This file implements the Escapade class
# An instance of this class is the differential problem itself
# This class essential goal is to write the booz CNN files
# from :
# 	- a set of discrete differential equations (class FiniteDifferenceSystem)
# 	- a Mesh (class Mesh)
# Additionnaly and optionnaly can be added :
#	- constants
#	- observers
#	- the choice of the minmisation method (0=Newton)

import csv
import cPickle
import os.path
import zlib
import os

EscapadeInstallDir='~/.escapade/'
load(os.path.join(os.path.expanduser(EscapadeInstallDir),'escapade_utils.spyx'))
load(os.path.join(os.path.expanduser(EscapadeInstallDir),'FiniteDifferenceSystemList.sage'))
load(os.path.join(os.path.expanduser(EscapadeInstallDir),'dd.sage'))



# La classe principale
class Escapade():
	def __init__(self,system,mesh,unknowns,constants=[],observers=[],dirichlet=[]):
		"""The constructor constructs the three members : system, unknowns and mesh.
		The three arguments are respectively a list of equations, a list of functions (the unknowns) and the mesh, of the Mesh class"
		It also sets to 0 the state variables that indicate if the computations have been done and the fils written.
		The constants argument states which variables are supposed to be known.
		The observers are a list of expressions of the variables and constants which will computed at each automaton step, allowing one to "observe" a given value which is not directly computed
		dirichlet is a list of lists, each of one corresponds to an equation in the system (first arg). This list contains those of the variables which are assumed to be known on that given system (in other words, those variables for which you give a Dirichlet condition)
		
		"""
		self.systemlist=FiniteDifferenceSystemList(system)
		self.unknowns=unknowns
		self.mesh=Mesh(mesh)
		self.dimension=len(mesh.shape)
		# It would be interesting here to check if the dimension of the mesh is equal to all parameters of all functions in system.
		# This takes time to code and compute... will do it later
		if (self.mesh.mesh.max())>(len(self.systemlist)-1):
			print("Warning : there are more system numbers in mesh than there are systems")
		if (self.mesh.mesh.max())>(len(dirichlet)-1):
			print("Warning : there are more system numbers in mesh than there are Dirichlet conditions")
		#
		# Let us now compute the Dirichlet vectors for each system
		# a Dirichlet vector will have as much component as there are variables
		# they will all be 1 except those for which there is a Dirichlet conditions will be 0
		# A pairwise product will thus give easily the update rule
		self.Dirichlet=[]
		for diric in (dirichlet):
			diric=set(diric)
			dirichlet_vector=[]
			for i in self.unknowns:
				if i in diric:
					dirichlet_vector.append(0)
				else:
					dirichlet_vector.append(1)
			self.Dirichlet.append(vector(dirichlet_vector))
		# Now the value by default of optionnal parameters
		# The constants in the system
		self.constants=constants
		# The observers
		self.observers=observers
		# The minimization method choice
		# 0 : the false time method
		# 1 : the Newton method
		# ...
		self.method=1
		#Now the value of state variables
		self.patterns_done=0
		self.field_done=0
		#A variable for local arguments : a bunch of zeros
		self.local_args=list(0 for i in range(0,self.dimension))# a list of 0
		self.zerovector=vector(self.local_args)
		#The differentiation vector
		self.diff_vector=vector(apply(f,self.local_args) for f in unknowns)
		#Choice of the method to compute the rules
		self.rulechoice=1
		#The number of pattern points computed so far : usefull to recover from a maxima crash
		self.points_computed_so_far=-1
		#Time step used in the false time method
		self.timestep=var("falsedt")
		#gradient coeff for gradient descent
		self.descent=var("epsgrad")
		#lambda parameter for modified Newton (see Bishop, p.287)
		self.lambdanewton=1
		# maximum number of arguments to + and * in Patterns
		# if superior, will be broken down with # = simpftmpiter # not used
		self.max_args=4
		simpftmpiter=function("simpftmpiter")
		# Parameters at null
		self.params=[]
		# Whether to simplify using fullsimplify, or not, after computation (default: yes)
		self.simplifyQ=1
		#Parallel stuff (not used)
		self.workers=1

	def __repr__(self):
		if self.constants==[]:
			cs=""
		else:
			cs="\nThe constants:\n"+self.constants.__repr__()
		if self.observers==[]:
			os=""
		else:
			os="\nThe observers:\n"+self.observers.__repr__()
		return("The systems that are to be solved (==0 are implicit):\n"+self.systemlist.__repr__()+"\nThe sought functions:\n"+self.unknowns.__repr__()+cs+os+"\nThe mesh :\n"+self.mesh.__repr__())

	
	def rules(self,pos):
		"""Computes the update rules at a given point : it is a list of rules.
		Constants and observers are not included in it. They are added later.
		Should be computed by summing the squared error on all the points pointed by dependency.
		"""
		# The system on the particular point we are on
		localsystem=(self.systemlist[self.mesh[tuple(pos)]])
		# Whatever the method, if the localsystem is null, return the no move rule
		if localsystem==[0]:
			return list(self.diff_vector)
#		if localsystem.squared_norm()==0:
#			print("squarednorm simplification")
#			return list(self.diff_vector)
		# For the False Time method, it is really easy, with a tricky part if the null system has only one component
		if self.method==0:
			rule=[]
			i=0
			for equation in localsystem:
				rule.append(self.diff_vector[i]+self.timestep*equation)
				i+=1
			return rule
		
		# somme is the sum to be minimized
		diffsomme=0
		# Sum of squared error is done over all the points designated by self.dependency when centered on pos
		# Dp not forget to translate the arguments of all unknowns and constants
		for point in self.dependency.points(pos):
			# If point is outside the mesh, ignore it
			if not self.mesh.is_in(point):
				continue
			# What system do we want to solve here
			system=self.systemlist[self.mesh[tuple(point)]]
			translatedsystem=(system.translation(vecteurs.diffv(point,pos),self.unknowns+self.constants))
#			print (cputime())
			somme_item=FiniteDifference(translatedsystem.squared_norm())
			tmpgrad=self.Dirichlet[self.mesh[tuple(point)]].pairwise_product(grad(somme_item,self.diff_vector))
#			print (cputime())
			if tmpgrad!=self.zerovector:
				if self.method==1:
					diffsomme_item=(hessian(somme_item,self.diff_vector)).solve_right(tmpgrad)
				elif self.method==2:
					diffsomme_item=(self.descent*tmpgrad)
				elif self.method==3:
					diffsomme_item=((hessian(somme_item,self.diff_vector)-self.lambdanewton*identity_matrix(len(self.diff_vector))).solve_right(tmpgrad))
				elif self.method==4:
					diffsomme_item=(diaghessian(somme_item,self.diff_vector)*(tmpgrad))
				else :
					print("method==0: False Time method\nmethod==1: Newton method\nmethod=2: steepest gradient\nmethod=3: Modified Newton\nmethod=4: Simplified Newton")
					return(-1);
				diffsomme+=self.Dirichlet[self.mesh[tuple(point)]].pairwise_product(diffsomme_item)
#			print (cputime())
			
		return(list(self.diff_vector-diffsomme))
		


	def rules1(self,pos):
		"""Computes the update rules at a given point : it is a list of rules.
		Constants and observers are not included in it. They are added later.
		Should be computed by summing the squared error on all the points pointed by dependency.
		This second version of the method rules does one big differentiation instead of lots of small ones
		"""
		# The system on the particular point we are on
		localsystem=(self.systemlist[self.mesh[tuple(pos)]])
		# Whatever the method, if the localsystem is null, return the no move rule
		if localsystem==[0]:
			#print("nomove rule")
			return list(self.diff_vector)
#		if localsystem.squared_norm()==0:
#			print("squarednorm simplification")
#			return list(self.diff_vector)
		# For the False Time method, it is really easy, with a tricky part if the null system has only one component
		if self.method==0:
			rule=[]
			i=0
			for equation in localsystem:
				rule.append(self.diff_vector[i]+self.timestep*equation)
				i+=1
			return rule
		
		# somme is the sum to be minimized
		somme=0
		# Sum of squared error is done over all the points designated by self.dependency when centered on pos
		# Dp not forget to translate the arguments of all unknowns and constants
#		print(cputime())
		for point in self.dependency.points(pos):
			# If point is outside the mesh, ignore it
			if self.mesh.is_in(point):
				# What system do we want to solve here
				system=self.systemlist[self.mesh[tuple(point)]]
#				print(pos,point,system)
				translatedsystem=(system.translation(vecteurs.diffv(point,pos),self.unknowns+self.constants))
#				print(pos,point,translatedsystem)
				somme+=FiniteDifference(translatedsystem.squared_norm())
#		print(cputime())
		tmpgrad=self.Dirichlet[self.mesh[tuple(point)]].pairwise_product(grad(somme,self.diff_vector))
		if tmpgrad!=self.zerovector:
#			if sommeneighborhood(self.unknowns).member(self.local_args):
			if self.method==1:
				diffsomme=(hessian(somme,self.diff_vector)).solve_right(tmpgrad)
			elif self.method==2:
				diffsomme=(self.descent*tmpgrad)
			elif self.method==3:
				diffsomme=((hessian(somme,self.diff_vector)-self.lambdanewton*identity_matrix(len(self.diff_vector))).solve_right(tmpgrad))
			elif self.method==4:
				diffsomme=(diaghessian(somme,self.diff_vector)*(tmpgrad))
			else :
				print("method==0: False Time method\nmethod==1: Newton method\nmethod=2: steepest gradient\nmethod=3: Modified Newton\nmethod=4: Simplified Newton")
				return(-1);
			#print("point :",point)
			#print("self.mesh[tuple(point)]:",self.mesh[tuple(point)])
			#print("self.Dirichlet[self.mesh[tuple(point)]]:",self.Dirichlet[self.mesh[tuple(point)]])
		return(list(self.diff_vector-self.Dirichlet[self.mesh[tuple(point)]].pairwise_product(diffsomme)))






	def printmethods(self):
		"Explains the various minimisation methods."
		print("Method 0: the False Time Method. This is the fastest one with the less insurance to converge. In this method, the given aquation are assumed to be the value of a time derivative. This time derivative is multiplied by self.timestep and added to the present state. It has the advantage of being very fast to compute: the equations are directly implemented onto the cellular automaton. In the case when the equations really are a time rate, then, the automaton behavior mimicks the physical system time behavior. It will thus converge only if the physical system converges with time. Another drawback is that it implements de facto an Euler solving of the system, with its known imprecision, though it is a little more sophisticated thanks to random unbuffered evaluation.")
		print("Method 1: standard Newton minimisation method. Longer to  compute though more precise. For details, see Bishop 'Neural Networks for Pattern Reconginition, chapter 7'")
		print("Method 2: steepest gradient, tuned through the self.descent attribute")
		print("Method 3: Modified Newton. the Hessian is replaced by H-lambda I. lambda is the attribute self.lambdanewton. For low lambdas, this is Newton Method while for large lambda, it ressembles the steepest gradient")
		print("Method 4: Simplified Newton: the Hessian is replaced by its diagonal. Easier to compute.")
		
	def makefield(self):
		"""Computes the field attribute.
		It is mesh of the same dimensions as the mesh attribute.
		It contains one integer per different patterns.
		"""
		# The dependency is the depency of the whole system list
		# Which is supposed to be the union of all system dependencies.
		# Except if the False Time mehod is chosen : in that case, the dependency is the neigborhood
		if self.method==0:
			self.dependency=self.systemlist.neighborhood(self.unknowns+self.constants)
		else:
			self.dependency=self.systemlist.dependency(self.unknowns+self.constants)
		# Computes the field : position of all possibly different update rules
		# self.point contains one point for each rule
		print("Field computing")
		[self.points,self.field]=self.mesh.field(self.dependency)
		print('Dumping')
		self.field.dump("field.escapade.dump")
		f=open("points.escapade.dump","w")
		f.write(dumps(self.points))
		f.close()
		self.dependency.save("dependency.escapade.dump");
		self.field_done=1;

	def loadfield(self):
		"""Loads the result of makefield instead of computing them.
		Needs the following files in the current directory :
			- field.escapade.dump
			- points.escapade.dump
		"""
		self.field=numpy.load("field.escapade.dump")
		f=open("points.escapade.dump","r")
		self.points=loads(f.read())
		f.close()
		f=open("dependency.escapade.dump","r")
		self.dependency=Pattern(sageobj(f.read()))
		f.close()
		self.field_done=1;


	def simplifyfield(self):
		"""Simplifies the field and rulelist attributes by checking to see if several rules are identical in rulelist"""
		string_rule_list=map(str,self.rulelist)
		new_string_rulelist=[]
		new_rulelist=[]
		ruledict={}
		new_list_length=0;
		for i in range(len(string_rule_list)):
			inlist=False
			for j in range(new_list_length):
				if new_string_rule_list[j]==string_rule_list[i]:
					inlist=True
					ruledict[self.field[tuple(point)]]=j
					break;
			if not inlist :
				new_rulelist.append(self.rulelist[i])
				new_string_rulelist.append(string_rulelist[i])
				ruledict[self.field[tuple(point)]]=new_list_length
				new_list_length+=1;
		#missing : actually simplify the field
			



	def makepatterns(self):
		"""Computes the update rules and their location for all points in the mesh.
		The class integer member method is used to choose the minmization method.
		Returns nothing. Rather fills the self.rules and self.field members
		0:Newton.
		"""
		if self.points_computed_so_far<0:
			# Now sets the rules member to an initially empty list
			self.rulelist=[]
			self.rulenumber=0
			# Now a dictionnary to change the pattnum array with the new numbers from the shortened list
			self.ruledict={}
		# For each different pattern found, i.e. each point in self.points
		# Compute the update rule and add it to the list only if it is not already in
		debut=walltime()
		totalpoints=len(self.points)
		print("Nb points:"+(len(self.points)).__repr__())
		print("Method :"+(self.method).__repr__())
		currentpoint=-1
		for point in self.points:
			currentpoint+=1
			if currentpoint<=self.points_computed_so_far:
				continue
			if self.rulechoice==0:
				rule=self.rules(point)
			else:
				rule=self.rules1(point)
#			print("Done point",point,"#",currentpoint, "time :",walltime()-debut)
			#Simplify if required
			if self.simplifyQ==1:
				rule=FiniteDifferenceSystem(rule).simplify()
			#Pickle and compress the rule before listing for memory saving
			rule=zlib.compress(dumps(rule))
			#Skip, or NOT, the lengthy test to limit the number of rules
			#BUG : only one point is set to the new rule, leaving rule numbers in field which do not mean anything
			#First work around : do not limit the number of rules
			#inlist=False
			#for i in range(self.rulenumber):
			#	if rule==self.rulelist[i]:
			#		inlist=True
			#		self.ruledict[self.field[tuple(point)]]=i #<---BUG
			#		break;
			#if not inlist:
			self.rulelist.append(rule)
			self.ruledict[self.field[tuple(point)]]=self.rulenumber
			self.rulenumber+=1
			#end of list adding
			self.points_computed_so_far+=1
			f=open("rulelist.escapade.dump","w")
			f.write(dumps(self.rulelist))
			f.close()
			f=open("ruledict.escapade.dump","w")
			f.write(dumps(self.ruledict))
			f.close()
			f=open("points_computed_so_far.escapade.dump","w")
			f.write(self.points_computed_so_far.__repr__())
			f.close()
			f=open("rulenumber.escapade.dump","w")
			f.write(self.rulenumber.__repr__())
			f.close()
			print("Dumped point :"+(point.__repr__())+", #"+(currentpoint.__repr__())+", time :"+((walltime()-debut).__repr__()))
			
			
##### C would be needed here
		#for each iterm in self.field, replace according to dictonnary ruledict
		for (i,val) in numpy.ndenumerate(self.field):
			self.field[i]=self.ruledict[val]
###########

	

	def loadpatterns(self):
		f=open("points_computed_so_far.escapade.dump","r")
		self.points_computed_so_far=sageobj(f.read())
		f.close()
		f=open("rulenumber.escapade.dump","r")
		self.rulenumber=sageobj(f.read())
		f.close()
		f=open("rulelist.escapade.dump","r")
		self.rulelist=loads(f.read())
		f.close()
		f=open("ruledict.escapade.dump","r")
		self.ruledict=loads(f.read())
		f.close()

	def loadCNN(self):
		self.loadfield()
		self.loadpatterns()
		
	
	def parallelinit(self,workers):
		self.workers=workers
		self.compute=dsage.start_all(workers=self.workers)



	def makeCNN(self):
		"""Computes the CNN rules.
		"""
		#If the field is not computed, do it
		if self.field_done==0:
			self.makefield()
		print("Computing update rules")
		if (self.workers>1) and (self.method!=0):
			self.makepatternsparallel()
		else:
			self.makepatterns()
		# Now let us add the rules for the constants and the obervers
		constantrules=list(apply(f,self.local_args) for f in self.constants)
		newrulelist=[]		
		while True:
			try:
				rule=loads(zlib.decompress(self.rulelist.pop(0)))
				rule.extend(constantrules)
				rule.extend(self.observers)
				newrulelist.append(zlib.compress(dumps(rule)))
			except IndexError:
				self.rulelist=newrulelist
				newrulelist=[]
				break
								
		self.patterns_done=1


	
	def write_files(self):
		"""Writes the booz files.
		"""
		if self.patterns_done==0:
			#print("Computations not done: run self.makeCNN first")
			self.makeCNN()
		#Try to create directory escapade
		try:
			os.mkdir("Escapade")
		except OSError:
			pass
		# MOve to it
		os.chdir("Escapade")

		#Size.booz
		#Only the mesh size
		f=open("Size.booz","w")
#		f.write(str(len(self.unknowns+self.constants+self.observers))+"\n")
#		f.write(str(len(self.rulelist))+"\n")
		for i in self.mesh.shape:
			f.write(i.__repr__()+" ")
		f.write("\n")
		f.close()


		#Field.booz
		#Same as simpf
		f=open("Field.booz","w")
		for i,val in numpy.ndenumerate(self.field):
			f.write(str(val))
			f.write(" ")			
		f.close()


		#Variables.booz
		#This function only puts variables names and sets bounds to -1 1 and "free"
		#This is good practice since variables should be normalized to 1
		#The user is free tom modify them
		f=open("Variables.booz","w")
#		f.write("#Variables bounds are set to -1 and 1 because it is good numerical practice to normalize the unknowns before any numerical investigation\n")
#		f.write("#They are set to \"free\" but can be constrained between bounds by replacing \"free\" by \"saturated\"\n#\n#\n")
		for i in (self.unknowns+self.constants+self.observers):
			f.write(i.__repr__()+"\t-1\t1\tfree\n")
		f.close()


		#Cell files
		for i in range(self.rulenumber):
			print("Cell "+i.__repr__())
			f=open(i.__repr__()+".cell","w")
			rules=loads(zlib.decompress(self.rulelist[i]))
			for j in range(len(self.unknowns)):
				stringpattern=(FiniteDifference(rules[j]).cform(self.max_args)).__repr__()
				stringpattern=stringpattern.replace("simpfarobas","@")
				for var in self.unknowns+self.constants+self.observers:
					stringpattern=stringpattern.replace(var.__repr__(),"?("+var.__repr__()+")")
				stringpattern=boozpattern(stringpattern)
				f.write(self.unknowns[j].__repr__()+"\t<-\t")
				f.write(stringpattern)
				f.write(";\n\n")
			for var in self.constants:
				f.write(var.__repr__()+"\t<-\t?"+vector(self.local_args).__repr__()+"("+var.__repr__()+")")
				f.write(";\n\n")
#				for var in self.observers:
			f.close()


		#A few constants
		f=open("Constants.booz","w")
		f.write(str(self.timestep))
		f.write("\t=\t1;\n")
		f.write(str(self.descent))
		f.write(str("\t=\t1;\n"))
		for params in self.params:
			f.write(str(params[0])+"\t=\t"+str(n(params[1]))+";")
			f.write("\n")
		f.close()
		
		#A minimal Functions.booz with math.h functions in it
		mathfunctions=["acos","asin","atan","atan2","ceil","cos","cosh","exp","fabs","floor","fmod","frexp","ldexp","log","log10","modf","pow","sin","sinh","sqrt","tan","tanh","acosh","asinh","atanh","cbrt","copysign","erf","erfc","exp2","expm1","fdim","fma","fmax","fmin","hypot","ilogb","lgamma","llrint","lrint","llround","lround","log1p","log2","logb","nan","nearbyint","nextafter","nexttoward","remainder","remquo","rint","round","scalbln","scalbn","tgamma","trunc"]
		f=open("Functions.booz","w")
		for i in mathfunctions:
			f.write(i)
			f.write("\n")
		f.close()
		# Backup one directory level
		os.chdir("..")


	def init(self,initlist):
		"""The method init takes as arguments a list of ndarrays corresponding to the initial values for unknowns and constants.
		This is output to INIT.booz file.
		"""
		f=open("INIT.booz","w")
		f.write((0*vector(self.mesh.shape)).__repr__())
		f.write(" ")
		f.write(self.mesh.shape.__repr__())
		f.write("\n")
		for i,val in numpy.ndenumerate(initlist[0]):
			for j in range(len(self.unknowns+self.constants+self.observers)):
				f.write(initlist[j][i].__repr__()+" ")
		f.close()
				
	def clear(self):
		"""Clears the computation flags.
		Allows to do the computation over again.
		"""
		self.field_done=0
		self.patterns_done=0
		self.points_computed_so_far=0
	

	def write_simpffiles(self):
		"""Writes the files for the old version of simpf.
		"""
		if self.patterns_done==0:
			#print("Computations not done: run self.makeCNN first")
			self.makeCNN()
		# Apply a series of rules for compliance with booz
		Crulelist=[]
		for rules in self.rulelist:
			Crules=[]
			for rule in rules:
				Crules.append(FiniteDifference(loads(zlib.decompress(rule))).cform(self.max_args))
			Crulelist.append(Crules)
		#Patterns.simpf
		stringpattern=Crulelist.__repr__()
		#replace each unknown and constant by ?(i) where i is its position in the list
		i=0
		stringpattern=stringpattern.replace("simpfarobas","@")
		stringpattern=stringpattern.replace("[","List(")
		stringpattern=stringpattern.replace("]",")")
		for f in (self.unknowns+self.constants):
			stringpattern=stringpattern.replace(f.__repr__(),"?("+i.__repr__()+")")
			i+=1
		stringpattern=simpfpattern(stringpattern)
		f=open("Patterns.simpf","w")
		f.write(stringpattern)
		f.close()
		#Field.simpf
		f=open("Field.simpf","w")
		f.write("List(")
		for i,val in numpy.ndenumerate(self.field):
			f.write(str(val))
			f.write(",")
		f.write(")")
		f.close()
		#Layout.simpf
		f=open("Layout.simpf","w")
		f.write(str(len(self.unknowns+self.constants+self.observers))+"\n")
		f.write(str(len(self.rulelist))+"\n")
		l=len(self.mesh.shape)
		if l==4:
			simpfshape=[self.mesh.shape[0],self.mesh.shape[1],self.mesh.shape[2],self.mesh.shape[3]]
		elif l==3:
			simpfshape=[1,self.mesh.shape[0],self.mesh.shape[1],self.mesh.shape[2]]
		elif l==2:
			simpfshape=[1,1,self.mesh.shape[0],self.mesh.shape[1]]
		elif l==1:
			simpfshape=[1,1,1,self.mesh.shape[0]]
		else:
			print("For simpf, Mesh dimensions must be between 1 and 4")
		for val in simpfshape:
			f.write(str(val)+" ")
		f.write("\n")
		f.close()
		
		#A few parameters for Params.simpf
		f=open("Params.simpf","w")
		f.write(str(self.timestep))
		#f.write("\t1\t#Time step used in the false time method\n")
		f.write("\t1\n")
		f.write(str(self.descent))
		#f.write(str("\t1\t#Gradient coefficient for the steepest gradient descent\n"))
		f.write(str("\t1\n"))
		for params in self.params:
			for param in params:
				f.write(str(param)+"\t")
			f.write("\n")
		f.close()
		
		#A minimal Functions.simpf
		f=open("Functions.simpf","w")
		f.write("pow\tpow\n")
		f.close()
		

	def simpfinit(self,initlist):
		"""The method simpfinit takes as arguments a list of ndarrays corresponding to the initial values for unknowns and constants.
		This is output to Init.simpf file.
		"""
		f=open("Init.simpf","w")
		f.write('List(')
		l=len(initlist)
		for i,val in numpy.ndenumerate(initlist[0]):
			for j in range(l):
				f.write(str(initlist[j][i]))
				f.write(",")
			f.write("\n")
		f.write(")")
		f.close()


	def read_simpf_result(self,snapshot):
		"""The method read results reads the results from the snapshot indicated file.
		And outputs it in a list of arrays.
		"""
		# The results are all output, including constants and obersvers
		n_results=len(self.unknowns+self.constants+self.observers)
		# start by a bunch of arrays filled with zeros
		result_list=list(numpy.zeros(self.mesh.shape) for i in range(n_results))
		# Open the file and read all the data in
		# This gulps a lot of memory: twice as needed
		# Can be corrected by either reading numbers one by one
		# or line by line
		reader=csv.reader(open(snapshot),delimiter=" ")
		#skip 2 lines
		# The first line could be used to check the file dimensionality agains self.shape
		_=reader.next()
		_=reader.next()
		data=reader.next()
		#remove last empty string
		data.pop()
		#convert to float
		data=(map(float,data))
		#fill the result_list
		index=0 # index in the data list
		for i,val in numpy.ndenumerate(result_list[0]):
			for j in range(n_results):
				result_list[j][i]=data[index]
				index+=1
		return (result_list)


#TODO :
# Init
#
# Parrallel computation of patterns in Escapade.sage (Hubert)
# Conjugate gradient and other methods
# 	p290 Bishop : Levenberg-Marquardt (probably time consuming)
# Mesh.spyx & Pattern.spyx : need to get deep into Cython

